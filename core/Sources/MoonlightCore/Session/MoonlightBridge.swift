import Foundation
import CMoonlightBridgeSupport
import CMoonlightCommon

public protocol MoonlightBridgeDelegate: AnyObject {
    func bridgeDidChangeStage(_ name: String)
    func bridgeDidStartConnection()
    func bridgeDidTerminateConnection(errorCode: Int32)
    func bridgeDidFailStage(_ name: String, errorCode: Int32)
}

private enum StopOutcome {
    case terminatedByCallback
    case timedOut
    case noActiveConnection
}

public enum MoonlightBridgeError: Error, LocalizedError {
    case connectionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case let .connectionFailed(code):
            return "Moonlight connection failed with code \(code)."
        }
    }
}

public final class MoonlightBridge {
    public weak var delegate: MoonlightBridgeDelegate?

    private let configuration: MVPConfiguration
    fileprivate let renderer: VideoFrameRenderer
    private let audioRenderer = OpusAudioRenderer()

    private var connectionCallbacks = CONNECTION_LISTENER_CALLBACKS()
    private var videoCallbacks = DECODER_RENDERER_CALLBACKS()
    private var audioCallbacks = AUDIO_RENDERER_CALLBACKS()
    private lazy var bridgeContextPointer: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
    private let stateQueue = DispatchQueue(label: "MoonlightBridge.state")
    private var isConnectionStarting = false
    private var isConnectionActive = false
    private var isStopInFlight = false
    private var stopWaiters: [CheckedContinuation<StopOutcome, Never>] = []

    public init(configuration: MVPConfiguration, renderer: VideoFrameRenderer) {
        self.configuration = configuration
        self.renderer = renderer
        self.audioRenderer.onError = { message in
            print("Moonlight audio renderer error: \(message)")
        }

        MoonlightBridgeSetActiveContext(bridgeContextPointer)
        MoonlightBridgeInstallCallbacks(&connectionCallbacks, &videoCallbacks, &audioCallbacks)
        videoCallbacks.capabilities = Int32(CAPABILITY_DIRECT_SUBMIT)
        audioCallbacks.capabilities = 0
    }

    public func start() async throws {
        stateQueue.sync {
            self.isConnectionStarting = true
            self.isStopInFlight = false
        }

        do {
            let pairedIdentity = try PairedIdentityStore().load(forHostAddress: configuration.host.address)
            let launchSession = LaunchSessionContext.makeRandom()
            let bootstrapper = HostSessionBootstrapper(
                configuration: configuration,
                pairedIdentity: pairedIdentity,
                launchSession: launchSession
            )
            let bootstrappedServerInfo = try await bootstrapper.bootstrap()

            var serverInfo = SERVER_INFORMATION()
            LiInitializeServerInformation(&serverInfo)
            serverInfo.address = UnsafePointer(strdup(configuration.host.address))
            serverInfo.serverInfoAppVersion = UnsafePointer(strdup(bootstrappedServerInfo.appVersion))
            serverInfo.serverInfoGfeVersion = UnsafePointer(strdup(bootstrappedServerInfo.gfeVersion))
            serverInfo.rtspSessionUrl = UnsafePointer(strdup(bootstrappedServerInfo.rtspURL))
            serverInfo.serverCodecModeSupport = Int32(SCM_AV1_MAIN8)

            var streamConfig = STREAM_CONFIGURATION()
            LiInitializeStreamConfiguration(&streamConfig)
            streamConfig.width = Int32(configuration.video.resolution.width)
            streamConfig.height = Int32(configuration.video.resolution.height)
            streamConfig.fps = Int32(configuration.video.fps)
            streamConfig.bitrate = Int32(configuration.video.bitrateKbps)
            streamConfig.packetSize = Int32(configuration.video.packetSize)
            streamConfig.streamingRemotely = Int32(STREAM_CFG_AUTO)
            streamConfig.audioConfiguration = Int32((0x3 << 16) | (2 << 8) | 0xCA)
            streamConfig.supportedVideoFormats = Int32(VIDEO_FORMAT_AV1_MAIN8)
            streamConfig.clientRefreshRateX100 = Int32(configuration.video.fps * 100)
            streamConfig.colorSpace = Int32(COLORSPACE_REC_709)
            streamConfig.colorRange = Int32(COLOR_RANGE_LIMITED)
            streamConfig.encryptionFlags = Int32(ENCFLG_AUDIO)

            Self.fillRemoteInputConfiguration(from: launchSession, into: &streamConfig)

            let result = LiStartConnection(
                &serverInfo,
                &streamConfig,
                &connectionCallbacks,
                &videoCallbacks,
                &audioCallbacks,
                bridgeContextPointer,
                0,
                bridgeContextPointer,
                0
            )

            if let address = serverInfo.address {
                free(UnsafeMutablePointer(mutating: address))
            }
            if let appVersion = serverInfo.serverInfoAppVersion {
                free(UnsafeMutablePointer(mutating: appVersion))
            }
            if let gfeVersion = serverInfo.serverInfoGfeVersion {
                free(UnsafeMutablePointer(mutating: gfeVersion))
            }
            if let rtspURL = serverInfo.rtspSessionUrl {
                free(UnsafeMutablePointer(mutating: rtspURL))
            }

            if result != 0 {
                stateQueue.sync {
                    self.isConnectionStarting = false
                    self.isConnectionActive = false
                }
                throw MoonlightBridgeError.connectionFailed(result)
            }

            stateQueue.sync {
                self.isConnectionStarting = false
                self.isConnectionActive = true
            }
        } catch {
            stateQueue.sync {
                self.isConnectionStarting = false
                self.isConnectionActive = false
            }
            throw error
        }
    }

    public func stop() async {
        let shouldStop = stateQueue.sync { () -> Bool in
            if isStopInFlight {
                return false
            }

            if !isConnectionStarting && !isConnectionActive {
                for waiter in stopWaiters {
                    waiter.resume(returning: .noActiveConnection)
                }
                stopWaiters.removeAll()
                return false
            }

            isStopInFlight = true
            return true
        }

        guard shouldStop else {
            return
        }

        LiStopConnection()

        _ = await waitForStopCompletion(timeoutNanoseconds: 3_000_000_000)
    }

    public func startSync() throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = ErrorBox()

        Task.detached(priority: .high) {
            defer { semaphore.signal() }
            do {
                try await self.start()
            } catch {
                errorBox.error = error
            }
        }

        semaphore.wait()

        let error = errorBox.error

        if let error {
            throw error
        }
    }

    public func stopSync() {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .high) {
            await self.stop()
            semaphore.signal()
        }
        semaphore.wait()
    }

    public func sendRelativeMouse(deltaX: Int16, deltaY: Int16) {
        _ = LiSendMouseMoveEvent(deltaX, deltaY)
    }

    public func sendAbsoluteMouse(x: Int16, y: Int16, referenceWidth: Int16, referenceHeight: Int16) {
        _ = LiSendMousePositionEvent(x, y, referenceWidth, referenceHeight)
    }

    public func sendMouseButton(action: Int8, button: Int32) {
        _ = LiSendMouseButtonEvent(action, button)
    }

    public func sendHighResolutionScroll(delta: Int16) {
        _ = LiSendHighResScrollEvent(delta)
    }

    public func sendHighResolutionHorizontalScroll(delta: Int16) {
        _ = LiSendHighResHScrollEvent(delta)
    }

    public func sendKeyboard(keyCode: UInt16, action: Int8, modifiers: UInt8, flags: UInt8) {
        _ = LiSendKeyboardEvent2(Int16(bitPattern: 0x8000 | keyCode), action, Int8(bitPattern: modifiers), Int8(bitPattern: flags))
    }

    public func sendText(_ text: String) {
        let utf8 = Array(text.utf8)
        utf8.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            _ = LiSendUtf8TextEvent(UnsafePointer<CChar>(OpaquePointer(baseAddress)), UInt32(buffer.count))
        }
    }

    private static func fillRemoteInputConfiguration(from launchSession: LaunchSessionContext, into streamConfig: inout STREAM_CONFIGURATION) {
        _ = launchSession.riKey.withUnsafeBytes { rawBuffer in
            memcpy(&streamConfig.remoteInputAesKey, rawBuffer.baseAddress, 16)
        }

        var rikeyID = launchSession.riKeyID.bigEndian
        _ = withUnsafeBytes(of: &rikeyID) { rawBuffer in
            memcpy(&streamConfig.remoteInputAesIv, rawBuffer.baseAddress, min(rawBuffer.count, 4))
        }
    }

    private func waitForStopCompletion(timeoutNanoseconds: UInt64) async -> StopOutcome {
        await withTaskGroup(of: StopOutcome.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    self.stateQueue.async {
                        if !self.isConnectionStarting && !self.isConnectionActive {
                            continuation.resume(returning: .noActiveConnection)
                            return
                        }

                        self.stopWaiters.append(continuation)
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return .timedOut
            }

            let outcome = await group.next() ?? .timedOut
            group.cancelAll()

            stateQueue.async {
                if case .timedOut = outcome {
                    let waiters = self.stopWaiters
                    self.stopWaiters.removeAll()
                    for waiter in waiters {
                        waiter.resume(returning: .timedOut)
                    }
                }

                self.isConnectionActive = false
                self.isStopInFlight = false
            }

            return outcome
        }
    }

    fileprivate func handleConnectionStarted() {
        stateQueue.async {
            self.isConnectionStarting = false
            self.isConnectionActive = true
            self.isStopInFlight = false
        }
    }

    fileprivate func handleConnectionEnded() {
        stateQueue.async {
            self.isConnectionStarting = false
            self.isConnectionActive = false
            self.isStopInFlight = false
            let waiters = self.stopWaiters
            self.stopWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: .terminatedByCallback)
            }
        }
    }

    fileprivate func initializeAudio(
        audioConfiguration: Int32,
        opusConfig: UnsafePointer<OPUS_MULTISTREAM_CONFIGURATION>?,
        arFlags: Int32
    ) -> Int32 {
        audioRenderer.configure(audioConfiguration: audioConfiguration, opusConfig: opusConfig, arFlags: arFlags)
    }

    fileprivate func startAudio() {
        audioRenderer.start()
    }

    fileprivate func stopAudio() {
        audioRenderer.stop()
    }

    fileprivate func cleanupAudio() {
        audioRenderer.cleanup()
    }

    fileprivate func decodeAndPlayAudioSample(_ sampleData: UnsafeMutablePointer<CChar>?, sampleLength: Int32) {
        audioRenderer.decodeAndPlaySample(sampleData, sampleLength: sampleLength)
    }
}

extension MoonlightBridge: @unchecked Sendable {}

private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

@_cdecl("MoonlightSwiftConnectionStageStarting")
func MoonlightSwiftConnectionStageStarting(_ context: UnsafeMutableRawPointer?, _ stage: Int32) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    let name = String(cString: LiGetStageName(stage))
    DispatchQueue.main.async {
        bridge.delegate?.bridgeDidChangeStage(name)
    }
}

@_cdecl("MoonlightSwiftConnectionStageComplete")
func MoonlightSwiftConnectionStageComplete(_ context: UnsafeMutableRawPointer?, _ stage: Int32) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    let name = String(cString: LiGetStageName(stage))
    DispatchQueue.main.async {
        bridge.delegate?.bridgeDidChangeStage(name)
    }
}

@_cdecl("MoonlightSwiftConnectionStageFailed")
func MoonlightSwiftConnectionStageFailed(_ context: UnsafeMutableRawPointer?, _ stage: Int32, _ errorCode: Int32) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    let name = String(cString: LiGetStageName(stage))
    DispatchQueue.main.async {
        bridge.delegate?.bridgeDidFailStage(name, errorCode: errorCode)
    }
}

@_cdecl("MoonlightSwiftConnectionStarted")
func MoonlightSwiftConnectionStarted(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.handleConnectionStarted()
    DispatchQueue.main.async {
        bridge.delegate?.bridgeDidStartConnection()
    }
}

@_cdecl("MoonlightSwiftConnectionTerminated")
func MoonlightSwiftConnectionTerminated(_ context: UnsafeMutableRawPointer?, _ errorCode: Int32) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.handleConnectionEnded()
    DispatchQueue.main.async {
        bridge.delegate?.bridgeDidTerminateConnection(errorCode: errorCode)
    }
}

@_cdecl("MoonlightSwiftVideoSetup")
func MoonlightSwiftVideoSetup(
    _ context: UnsafeMutableRawPointer?,
    _ videoFormat: Int32,
    _ width: Int32,
    _ height: Int32,
    _ redrawRate: Int32,
    _ drFlags: Int32
) -> Int32 {
    guard let context else { return -1 }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.renderer.configure(videoFormat: videoFormat, width: width, height: height, redrawRate: redrawRate)
    _ = drFlags
    return 0
}

@_cdecl("MoonlightSwiftVideoStart")
func MoonlightSwiftVideoStart(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForVideoCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.renderer.start()
}

@_cdecl("MoonlightSwiftVideoStop")
func MoonlightSwiftVideoStop(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.renderer.stop()
}

@_cdecl("MoonlightSwiftVideoCleanup")
func MoonlightSwiftVideoCleanup(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.renderer.cleanup()
    bridge.handleConnectionEnded()
}

@_cdecl("MoonlightSwiftVideoSubmitDecodeUnit")
func MoonlightSwiftVideoSubmitDecodeUnit(_ context: UnsafeMutableRawPointer?, _ decodeUnit: UnsafePointer<DECODE_UNIT>?) -> Int32 {
    guard let context, let decodeUnit else { return Int32(DR_NEED_IDR) }
    StreamingPriority.promoteCurrentThreadForVideoCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    let unit = decodeUnit.pointee

    var frameData = Data()
    frameData.reserveCapacity(Int(unit.fullLength))

    var currentEntry = unit.bufferList
    while let entry = currentEntry {
        let buffer = entry.pointee
        let byteCount = Int(buffer.length)
        guard let rawData = buffer.data else {
            currentEntry = entry.pointee.next
            continue
        }
        let bytes = UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(rawData)), count: byteCount)

        if buffer.bufferType == Int32(BUFFER_TYPE_PICDATA) {
            frameData.append(contentsOf: bytes)
        }

        currentEntry = entry.pointee.next
    }

    guard !frameData.isEmpty else {
        return Int32(DR_NEED_IDR)
    }

    let sequenceHeader: Data?
    if unit.frameType == Int32(FRAME_TYPE_IDR) {
        sequenceHeader = AV1Bitstream.extractSequenceHeaderOBU(from: frameData)
    } else {
        sequenceHeader = nil
    }

    let submission = VideoFrameSubmission(
        frameType: unit.frameType,
        presentationTimeUs: unit.presentationTimeUs,
        rtpTimestamp: unit.rtpTimestamp,
        frameData: frameData,
        sequenceHeader: sequenceHeader
    )

    return bridge.renderer.submit(frameSubmission: submission)
}

@_cdecl("MoonlightSwiftAudioInit")
func MoonlightSwiftAudioInit(
    _ context: UnsafeMutableRawPointer?,
    _ audioConfiguration: Int32,
    _ opusConfig: UnsafePointer<OPUS_MULTISTREAM_CONFIGURATION>?,
    _ arFlags: Int32
) -> Int32 {
    guard let context else { return 0 }
    StreamingPriority.promoteCurrentThreadForConnectionCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    return bridge.initializeAudio(audioConfiguration: audioConfiguration, opusConfig: opusConfig, arFlags: arFlags)
}

@_cdecl("MoonlightSwiftAudioStart")
func MoonlightSwiftAudioStart(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForAudioCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.startAudio()
}

@_cdecl("MoonlightSwiftAudioStop")
func MoonlightSwiftAudioStop(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForAudioCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.stopAudio()
}

@_cdecl("MoonlightSwiftAudioCleanup")
func MoonlightSwiftAudioCleanup(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForAudioCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.cleanupAudio()
}

@_cdecl("MoonlightSwiftAudioDecodeAndPlaySample")
func MoonlightSwiftAudioDecodeAndPlaySample(_ context: UnsafeMutableRawPointer?, _ sampleData: UnsafeMutablePointer<CChar>?, _ sampleLength: Int32) {
    guard let context else { return }
    StreamingPriority.promoteCurrentThreadForAudioCallbacks()
    let bridge = Unmanaged<MoonlightBridge>.fromOpaque(context).takeUnretainedValue()
    bridge.decodeAndPlayAudioSample(sampleData, sampleLength: sampleLength)
}
