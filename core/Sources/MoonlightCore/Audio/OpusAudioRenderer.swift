import AudioToolbox
@preconcurrency import AVFAudio
import CMoonlightCommon
import Foundation

final class OpusAudioRenderer {
    var onError: (@Sendable (String) -> Void)?

    private let stateQueue = DispatchQueue(label: "moonlight.audio.opus.state", qos: .userInteractive)

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var converter: AVAudioConverter?
    private var opusFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var sampleRate: Double = 48_000
    private var channelCount: AVAudioChannelCount = 2
    private var samplesPerFrame: AVAudioFrameCount = 480
    private var queuedFrameCount: AVAudioFramePosition = 0
    private var maximumQueuedFrameCount: AVAudioFramePosition = 4_800
    private var isStarted = false
    private var generation: UInt64 = 0
    private var lastReportedError: String?

    func configure(
        audioConfiguration: Int32,
        opusConfig: UnsafePointer<OPUS_MULTISTREAM_CONFIGURATION>?,
        arFlags: Int32
    ) -> Int32 {
        _ = arFlags

        guard let opusConfig else {
            reportError("Missing Opus decoder configuration")
            return -1
        }

        let config = opusConfig.pointee
        let negotiatedChannelCount = Int((audioConfiguration >> 8) & 0xFF)

        guard config.channelCount == 2, negotiatedChannelCount == 2 else {
            reportError("Only stereo audio is currently supported")
            return -1
        }

        guard config.sampleRate > 0, config.samplesPerFrame > 0 else {
            reportError("Invalid Opus audio parameters")
            return -1
        }

        do {
            try stateQueue.sync {
                generation &+= 1
                teardownLocked()

                var streamDescription = AudioStreamBasicDescription(
                    mSampleRate: Double(config.sampleRate),
                    mFormatID: kAudioFormatOpus,
                    mFormatFlags: 0,
                    mBytesPerPacket: 0,
                    mFramesPerPacket: UInt32(config.samplesPerFrame),
                    mBytesPerFrame: 0,
                    mChannelsPerFrame: UInt32(config.channelCount),
                    mBitsPerChannel: 0,
                    mReserved: 0
                )

                guard let opusFormat = AVAudioFormat(streamDescription: &streamDescription) else {
                    throw OpusAudioRendererError.unsupportedOpusFormat
                }

                guard let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: Double(config.sampleRate),
                    channels: AVAudioChannelCount(config.channelCount),
                    interleaved: false
                ) else {
                    throw OpusAudioRendererError.unsupportedPCMFormat
                }

                guard let converter = AVAudioConverter(from: opusFormat, to: outputFormat) else {
                    throw OpusAudioRendererError.failedToCreateConverter
                }

                converter.primeMethod = .none

                let engine = AVAudioEngine()
                let playerNode = AVAudioPlayerNode()
                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
                engine.prepare()

                self.engine = engine
                self.playerNode = playerNode
                self.converter = converter
                self.opusFormat = opusFormat
                self.outputFormat = outputFormat
                self.sampleRate = Double(config.sampleRate)
                self.channelCount = AVAudioChannelCount(config.channelCount)
                self.samplesPerFrame = AVAudioFrameCount(config.samplesPerFrame)
                self.maximumQueuedFrameCount = max(AVAudioFramePosition(config.samplesPerFrame * 12), AVAudioFramePosition(config.sampleRate / 20))
                self.queuedFrameCount = 0
                self.isStarted = false
                self.clearErrorLocked()
            }
        } catch {
            reportError(error.localizedDescription)
            return -1
        }

        return 0
    }

    func start() {
        stateQueue.async {
            StreamingPriority.promoteCurrentThreadForAudioCallbacks()

            guard let engine = self.engine, let playerNode = self.playerNode else {
                self.reportErrorLocked("Audio renderer is not configured")
                return
            }

            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    self.reportErrorLocked("Audio engine start failed: \(error.localizedDescription)")
                    return
                }
            }

            if !playerNode.isPlaying {
                playerNode.play()
            }

            self.isStarted = true
            self.clearErrorLocked(message: "Audio renderer is not configured")
            self.clearErrorLocked(prefix: "Audio engine start failed:")
        }
    }

    func stop() {
        stateQueue.async {
            StreamingPriority.promoteCurrentThreadForAudioCallbacks()
            self.generation &+= 1
            self.stopLocked(resetConverter: true)
        }
    }

    func cleanup() {
        stateQueue.async {
            StreamingPriority.promoteCurrentThreadForAudioCallbacks()
            self.generation &+= 1
            self.teardownLocked()
        }
    }

    func decodeAndPlaySample(_ sampleData: UnsafeMutablePointer<CChar>?, sampleLength: Int32) {
        guard let sampleData, sampleLength > 0 else {
            return
        }

        guard let packet = OwnedAudioPacket(copying: sampleData, count: Int(sampleLength)) else {
            reportError("Failed to allocate audio packet buffer")
            return
        }

        stateQueue.async {
            StreamingPriority.promoteCurrentThreadForAudioCallbacks()
            let generation = self.generation
            self.decodeAndSchedulePacketLocked(packet, generation: generation)
        }
    }
}

extension OpusAudioRenderer: @unchecked Sendable {}

private extension OpusAudioRenderer {
    func decodeAndSchedulePacketLocked(_ packet: OwnedAudioPacket, generation: UInt64) {
        guard generation == self.generation else {
            return
        }

        guard isStarted else {
            return
        }

        guard let converter, let opusFormat, let outputFormat, let playerNode else {
            reportErrorLocked("Audio packet received before renderer setup")
            return
        }

        guard queuedFrameCount < maximumQueuedFrameCount else {
            reportErrorLocked("Dropping audio packet due to playback backlog")
            return
        }

        let maximumPacketSize = max(packet.data.length, 1)
        let compressedBuffer = AVAudioCompressedBuffer(
            format: opusFormat,
            packetCapacity: 1,
            maximumPacketSize: maximumPacketSize
        )
        compressedBuffer.packetCount = 1
        compressedBuffer.byteLength = UInt32(packet.data.length)

        guard let packetDescriptions = compressedBuffer.packetDescriptions else {
            reportErrorLocked("Audio decoder packet description unavailable")
            return
        }

        packetDescriptions[0].mStartOffset = 0
        packetDescriptions[0].mVariableFramesInPacket = 0
        packetDescriptions[0].mDataByteSize = UInt32(packet.data.length)

        UnsafeMutableRawPointer(compressedBuffer.data).copyMemory(from: packet.data.bytes, byteCount: packet.data.length)

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: samplesPerFrame) else {
            reportErrorLocked("Failed to allocate decoded audio buffer")
            return
        }

        let packetSource = AudioCompressedPacketSource(compressedBuffer: compressedBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: pcmBuffer, error: &conversionError) { _, outStatus in
            packetSource.nextBuffer(outStatus: outStatus)
        }

        if let conversionError {
            reportErrorLocked("Audio decode failed: \(conversionError.localizedDescription)")
            converter.reset()
            queuedFrameCount = 0
            playerNode.stop()
            playerNode.play()
            return
        }

        guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
            reportErrorLocked("Audio decode returned status \(status.rawValue)")
            return
        }

        guard pcmBuffer.frameLength > 0 else {
            return
        }

        let frameLength = AVAudioFramePosition(pcmBuffer.frameLength)
        queuedFrameCount += frameLength

        playerNode.scheduleBuffer(pcmBuffer) {
            self.stateQueue.async {
                self.queuedFrameCount = max(0, self.queuedFrameCount - frameLength)
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        clearErrorLocked(message: "Dropping audio packet due to playback backlog")
        clearErrorLocked(message: "Audio packet received before renderer setup")
        clearErrorLocked(prefix: "Audio decode failed:")
        clearErrorLocked(prefix: "Audio decode returned status")
    }

    func stopLocked(resetConverter: Bool) {
        isStarted = false
        queuedFrameCount = 0
        playerNode?.stop()
        engine?.stop()

        if resetConverter {
            converter?.reset()
        }
    }

    func teardownLocked() {
        stopLocked(resetConverter: true)
        engine?.reset()
        playerNode = nil
        engine = nil
        converter = nil
        opusFormat = nil
        outputFormat = nil
        clearErrorLocked()
    }

    func reportError(_ message: String) {
        stateQueue.async {
            self.reportErrorLocked(message)
        }
    }

    func reportErrorLocked(_ message: String) {
        guard lastReportedError != message else {
            return
        }

        lastReportedError = message
        onError?(message)
    }

    func clearErrorLocked(message: String? = nil, prefix: String? = nil) {
        guard let lastReportedError else {
            return
        }

        if let message, lastReportedError == message {
            self.lastReportedError = nil
            return
        }

        if let prefix, lastReportedError.hasPrefix(prefix) {
            self.lastReportedError = nil
            return
        }

        if message == nil, prefix == nil {
            self.lastReportedError = nil
        }
    }
}

private final class OwnedAudioPacket: @unchecked Sendable {
    let data: NSMutableData

    init?(copying bytes: UnsafeMutablePointer<CChar>, count: Int) {
        guard let data = NSMutableData(length: count) else {
            return nil
        }

        memcpy(data.mutableBytes, bytes, count)
        self.data = data
    }
}

private final class AudioCompressedPacketSource: @unchecked Sendable {
    private let compressedBuffer: AVAudioCompressedBuffer
    private var didProvideInput = false

    init(compressedBuffer: AVAudioCompressedBuffer) {
        self.compressedBuffer = compressedBuffer
    }

    func nextBuffer(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideInput {
            outStatus.pointee = .noDataNow
            return nil
        }

        didProvideInput = true
        outStatus.pointee = .haveData
        return compressedBuffer
    }
}

private enum OpusAudioRendererError: LocalizedError {
    case unsupportedOpusFormat
    case unsupportedPCMFormat
    case failedToCreateConverter

    var errorDescription: String? {
        switch self {
        case .unsupportedOpusFormat:
            return "The negotiated Opus format is unsupported"
        case .unsupportedPCMFormat:
            return "The decoded PCM playback format is unsupported"
        case .failedToCreateConverter:
            return "Failed to create the native Opus decoder"
        }
    }
}
