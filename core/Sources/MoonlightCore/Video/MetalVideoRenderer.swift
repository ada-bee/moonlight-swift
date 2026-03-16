import AppKit
import CMoonlightCommon
import CoreFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Metal
@preconcurrency import QuartzCore
import VideoToolbox

private final class MetalDecodedFrameContext {
    let renderer: MetalVideoRenderer
    let fallbackPresentationTimeStamp: CMTime

    init(
        renderer: MetalVideoRenderer,
        fallbackPresentationTimeStamp: CMTime
    ) {
        self.renderer = renderer
        self.fallbackPresentationTimeStamp = fallbackPresentationTimeStamp
    }
}

private struct MetalDecoderSubmitState {
    let formatDescription: CMVideoFormatDescription
    let decompressionSession: VTDecompressionSession
    let frameRate: Int32
}

private func metalVideoRendererDecodeCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
    ) {
        StreamingPriority.promoteCurrentThreadForVideoCallbacks()

    guard let sourceFrameRefCon else {
        return
    }

    let context = Unmanaged<MetalDecodedFrameContext>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    context.renderer.handleDecodedFrame(
        status: status,
        infoFlags: infoFlags,
        imageBuffer: imageBuffer,
        presentationTimeStamp: presentationTimeStamp,
        presentationDuration: presentationDuration,
        fallbackPresentationTimeStamp: context.fallbackPresentationTimeStamp
    )
}

public final class MetalVideoRenderer: NSObject, VideoFrameRenderer {
    public let rendererName = "VideoToolbox + Metal"
    public var onError: (@Sendable (String) -> Void)?

    private let stateQueue = DispatchQueue(label: "moonlight.renderer.metal.state", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "moonlight.renderer.metal.render", qos: .userInteractive)
    private let asyncDecodeFlags = VTDecodeFrameFlags(rawValue: 1 << 0)
    private let quadVertices: [SIMD4<Float>] = [
        SIMD4(-1, -1, 0, 1),
        SIMD4(1, -1, 1, 1),
        SIMD4(-1, 1, 0, 0),
        SIMD4(1, 1, 1, 0)
    ]

    private weak var hostView: VideoRendererView?
    private var metalDevice: MTLDevice?
    private var metalLayer: CAMetalLayer?
    private var displayLink: CADisplayLink?
    private var shaderLibrary: MTLLibrary?
    private var commandQueue: MTLCommandQueue?
    private var renderPipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?

    private var frameRate: Int32 = 60
    private var configuredVideoFormat: Int32 = 0
    private var configuredVideoSize: CGSize = .zero
    private var configuredRefreshRate: Int32 = 60
    private var decoderConfiguration: AV1DecoderConfiguration?
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private var pendingFrame: DecodedMetalFrame?
    private var isRenderingFrame = false
    private var isRendererRunning = false
    private var isDrawableAcquisitionInFlight = false
    private var lastReportedError: String?

    public override init() {
        super.init()
    }

    deinit {
        if Thread.isMainThread {
            displayLink?.invalidate()
        } else {
            DispatchQueue.main.sync {
                self.displayLink?.invalidate()
            }
        }
    }

    public func attach(to hostView: VideoRendererView) {
        self.hostView = hostView
        runOnMainSync {
            hostView.onLayout = { [weak self] bounds in
                self?.updateMetalLayerFrame(bounds)
            }
        }
        installMetalSurfaceIfPossible(on: hostView)
        ensureDisplayLinkIfNeeded()
    }

    public func configure(videoFormat: Int32, width: Int32, height: Int32, redrawRate: Int32) {
        stateQueue.sync {
            self.configuredVideoFormat = videoFormat
            self.frameRate = redrawRate
            self.configuredVideoSize = CGSize(width: Int(width), height: Int(height))
            self.configuredRefreshRate = redrawRate
            self.lastReportedError = nil
        }

        updateMetalConfiguration()
    }

    public func start() {
        renderQueue.sync {
            self.isRendererRunning = true
        }
        stateQueue.sync {
            self.lastReportedError = nil
        }
        startDisplayLinkIfNeeded()
    }

    public func stop() {
        stopDisplayLinkIfNeeded()
        renderQueue.sync {
            self.isRendererRunning = false
            self.isRenderingFrame = false
            self.isDrawableAcquisitionInFlight = false
            self.pendingFrame = nil
            if let textureCache {
                CVMetalTextureCacheFlush(textureCache, 0)
            }
        }
    }

    public func cleanup() {
        stopDisplayLinkIfNeeded()
        runOnMainSync {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }

        stateQueue.sync {
            self.decoderConfiguration = nil
            self.formatDescription = nil
            self.invalidateDecompressionSessionLocked()
        }

        runOnMainSync {
            self.hostView?.onLayout = nil
            self.metalLayer?.removeFromSuperlayer()
            self.metalLayer = nil
        }

        renderQueue.sync {
            self.isRendererRunning = false
            self.isRenderingFrame = false
            self.isDrawableAcquisitionInFlight = false
            self.pendingFrame = nil
            if let textureCache {
                CVMetalTextureCacheFlush(textureCache, 0)
            }
            self.textureCache = nil
            self.commandQueue = nil
            self.renderPipelineState = nil
        }

        stateQueue.sync {
            self.lastReportedError = nil
        }

        runOnMainSync {
            self.shaderLibrary = nil
        }
    }

    public func submit(frameSubmission: VideoFrameSubmission) -> Int32 {
        let decoderState: MetalDecoderSubmitState
        do {
            decoderState = try prepareDecoderSubmitState(for: frameSubmission)
        } catch {
            reportError("Metal setup failed: \(error.localizedDescription)")
            return Int32(DR_NEED_IDR)
        }

        let samplePresentationTime = presentationTime(for: frameSubmission)

        guard let sampleBuffer = createCompressedSampleBuffer(
            frameSubmission: frameSubmission,
            formatDescription: decoderState.formatDescription,
            frameRate: decoderState.frameRate,
            presentationTime: samplePresentationTime
        ) else {
            reportError("Compressed sample create failed")
            return Int32(DR_NEED_IDR)
        }

        let decodeContext = Unmanaged.passRetained(
            MetalDecodedFrameContext(
                renderer: self,
                fallbackPresentationTimeStamp: samplePresentationTime
            )
        )
        var decodeInfoFlags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            decoderState.decompressionSession,
            sampleBuffer: sampleBuffer,
            flags: asyncDecodeFlags,
            frameRefcon: decodeContext.toOpaque(),
            infoFlagsOut: &decodeInfoFlags
        )

        guard decodeStatus == noErr else {
            _ = decodeContext.takeRetainedValue()
            reportError("Decode submit failed: \(decodeStatus)")
            stateQueue.sync {
                self.invalidateDecompressionSessionLocked()
            }
            return Int32(DR_NEED_IDR)
        }

        return Int32(DR_OK)
    }
}

extension MetalVideoRenderer: @unchecked Sendable {}

private final class DrawableAcquisitionResult {
    let drawable: CAMetalDrawable?

    init(drawable: CAMetalDrawable?) {
        self.drawable = drawable
    }
}

extension DrawableAcquisitionResult: @unchecked Sendable {}

private extension MetalVideoRenderer {
    func installMetalSurfaceIfPossible(on hostView: VideoRendererView) {
        runOnMainSync {
            if self.metalDevice == nil {
                self.metalDevice = MTLCreateSystemDefaultDevice()
            }

            guard let metalDevice = self.metalDevice else {
                self.reportError("No Metal device available")
                return
            }

            let commandQueue = self.renderQueue.sync { self.commandQueue } ?? metalDevice.makeCommandQueue()
            guard let commandQueue else {
                self.reportError("Failed to create Metal command queue")
                return
            }

            let textureCache: CVMetalTextureCache?
            if let existingTextureCache = self.renderQueue.sync(execute: { self.textureCache }) {
                textureCache = existingTextureCache
            } else {
                var createdTextureCache: CVMetalTextureCache?
                let cacheAttributes = [kCVMetalTextureUsage: MTLTextureUsage.shaderRead.rawValue] as CFDictionary
                let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, cacheAttributes, metalDevice, nil, &createdTextureCache)
                if status == kCVReturnSuccess {
                    textureCache = createdTextureCache
                } else {
                    self.reportError("Failed to create Metal texture cache: \(status)")
                    return
                }
            }

            guard let textureCache else {
                self.reportError("Failed to create Metal texture cache")
                return
            }

            if let metalLayer = self.metalLayer {
                metalLayer.device = metalDevice
                if metalLayer.superlayer !== hostView.layer {
                    metalLayer.removeFromSuperlayer()
                    hostView.layer?.insertSublayer(metalLayer, at: 0)
                }
            } else {
                let metalLayer = CAMetalLayer()
                metalLayer.name = "MoonlightMetalVideoLayer"
                metalLayer.device = metalDevice
                metalLayer.pixelFormat = .bgra8Unorm
                metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
                metalLayer.framebufferOnly = true
                metalLayer.backgroundColor = NSColor.black.cgColor
                metalLayer.isOpaque = true
                metalLayer.contentsGravity = .resizeAspect
                metalLayer.contentsScale = hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
                metalLayer.drawableSize = CGSize(
                    width: hostView.bounds.width * metalLayer.contentsScale,
                    height: hostView.bounds.height * metalLayer.contentsScale
                )
                metalLayer.frame = hostView.bounds
                hostView.layer?.insertSublayer(metalLayer, at: 0)
                self.metalLayer = metalLayer
            }

            self.prepareShaderPipelineIfNeeded(device: metalDevice)
            self.renderQueue.sync {
                self.commandQueue = commandQueue
                self.textureCache = textureCache
            }
            self.clearError("No Metal device available")
            self.clearError("Failed to create Metal command queue")
            self.clearError("Failed to create Metal texture cache")
            self.updateMetalLayerFrame(hostView.bounds)
            self.updateMetalConfiguration()
        }
    }

    func updateMetalConfiguration() {
        runOnMainSync {
            guard let metalLayer = self.metalLayer else {
                return
            }

            _ = max(self.stateQueue.sync { self.configuredRefreshRate }, 1)
            metalLayer.displaySyncEnabled = true
            metalLayer.allowsNextDrawableTimeout = true
            metalLayer.maximumDrawableCount = 2
            metalLayer.presentsWithTransaction = false
            _ = self.stateQueue.sync { self.configuredVideoSize }
        }
    }

    func updateMetalLayerFrame(_ bounds: CGRect) {
        runOnMainSync {
            guard let metalLayer = self.metalLayer else {
                return
            }

            let scale = self.hostView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? metalLayer.contentsScale
            metalLayer.contentsScale = scale
            metalLayer.frame = bounds
            metalLayer.drawableSize = CGSize(
                width: max(bounds.width * scale, 1),
                height: max(bounds.height * scale, 1)
            )
        }
    }

    func ensureDisplayLinkIfNeeded() {
        guard displayLink == nil else {
            return
        }

        runOnMainSync {
            guard let hostView = self.hostView else {
                return
            }

            let displayLink = hostView.displayLink(target: self, selector: #selector(self.handleAppKitDisplayLinkTick(_:)))
            displayLink.add(to: .main, forMode: .common)
            displayLink.isPaused = true
            self.displayLink = displayLink
        }
        guard displayLink != nil else {
            reportError("Failed to create display link")
            return
        }

        clearError("Failed to create display link")
    }

    func startDisplayLinkIfNeeded() {
        ensureDisplayLinkIfNeeded()
        guard let displayLink, displayLink.isPaused else {
            return
        }

        runOnMainSync {
            displayLink.isPaused = false
        }

        clearError("Failed to start display link")
    }

    func stopDisplayLinkIfNeeded() {
        guard let displayLink, !displayLink.isPaused else {
            return
        }

        runOnMainSync {
            displayLink.isPaused = true
        }
    }

    @objc
    func handleAppKitDisplayLinkTick(_ displayLink: CADisplayLink) {
        _ = displayLink
        handleDisplayLinkTick()
    }

    func handleDisplayLinkTick() {
        StreamingPriority.promoteCurrentThreadForRenderWork()

        let tickState = renderQueue.sync { () -> (frameAvailable: Bool, shouldAcquireDrawable: Bool) in
            let frameAvailable = self.pendingFrame != nil
            let shouldAcquireDrawable = self.isRendererRunning
                && frameAvailable
                && !self.isRenderingFrame
                && !self.isDrawableAcquisitionInFlight

            if shouldAcquireDrawable {
                self.isDrawableAcquisitionInFlight = true
            }

            return (frameAvailable, shouldAcquireDrawable)
        }

        guard tickState.shouldAcquireDrawable else {
            return
        }

        let result = DrawableAcquisitionResult(drawable: nextDrawableIfAvailable())
        renderQueue.async {
            self.finishDrawableAcquisition(result.drawable)
        }
    }

    func handleDecodedFrame(
        status: OSStatus,
        infoFlags: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime,
        presentationDuration: CMTime,
        fallbackPresentationTimeStamp: CMTime
    ) {
        _ = presentationDuration
        _ = infoFlags

        guard status == noErr, let imageBuffer else {
            reportError("Decode callback failed: \(status)")
            return
        }
        let pixelBuffer = imageBuffer

        let frame = DecodedMetalFrame(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp.isValid ? presentationTimeStamp : fallbackPresentationTimeStamp
        )

        renderQueue.async {
            self.queueDecodedFrame(frame)
        }
    }

    func queueDecodedFrame(_ frame: DecodedMetalFrame) {
        StreamingPriority.promoteCurrentThreadForRenderWork()

        pendingFrame = frame
    }

    func finishDrawableAcquisition(_ drawable: CAMetalDrawable?) {
        StreamingPriority.promoteCurrentThreadForRenderWork()

        isDrawableAcquisitionInFlight = false

        guard isRendererRunning else {
            pendingFrame = nil
            return
        }

        guard !isRenderingFrame else {
            return
        }

        guard let drawable else {
            return
        }

        guard let frame = pendingFrame else {
            return
        }

        pendingFrame = nil
        isRenderingFrame = true
        render(frame: frame, drawable: drawable)
    }

    func render(frame: DecodedMetalFrame, drawable: CAMetalDrawable) {
        StreamingPriority.promoteCurrentThreadForRenderWork()

        guard submitRender(pixelBuffer: frame.pixelBuffer, drawable: drawable, completion: { [weak self] in
            guard let self else {
                return
            }

            self.renderQueue.async {
                StreamingPriority.promoteCurrentThreadForRenderWork()
                self.isRenderingFrame = false
                guard self.isRendererRunning else {
                    return
                }
            }
        }) else {
            isRenderingFrame = false
            return
        }
    }

    func prepareDecoderSubmitState(for frameSubmission: VideoFrameSubmission) throws -> MetalDecoderSubmitState {
        try stateQueue.sync {
            if frameSubmission.frameType == Int32(FRAME_TYPE_IDR) {
                try self.rebuildFormatDescriptionIfNeeded(for: frameSubmission)
            }

            guard let formatDescription = self.formatDescription else {
                throw MetalRendererError.missingAV1DecoderConfiguration
            }

            let decompressionSession = try self.ensureDecompressionSessionLocked(for: formatDescription)
            return MetalDecoderSubmitState(
                formatDescription: formatDescription,
                decompressionSession: decompressionSession,
                frameRate: self.frameRate
            )
        }
    }

    func ensureDecompressionSessionLocked(for formatDescription: CMVideoFormatDescription) throws -> VTDecompressionSession {
        if let decompressionSession {
            return decompressionSession
        }

        guard VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) else {
            throw MetalRendererError.hardwareDecodeUnavailable
        }

        let destinationAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let decoderSpecification: [CFString: Any] = [
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: kCFBooleanTrue as Any
        ]

        var session: VTDecompressionSession?
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: metalVideoRendererDecodeCallback,
            decompressionOutputRefCon: nil
        )

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session else {
            throw MetalRendererError.failedToCreateDecompressionSession(status)
        }

        VTSessionSetProperty(
            session,
            key: kVTDecompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        guard sessionUsesHardwareDecoder(session) else {
            VTDecompressionSessionInvalidate(session)
            throw MetalRendererError.hardwareDecoderRequirementNotMet
        }

        decompressionSession = session
        return session
    }

    func invalidateDecompressionSessionLocked() {
        guard let decompressionSession else {
            return
        }

        VTDecompressionSessionInvalidate(decompressionSession)
        self.decompressionSession = nil
    }

    func sessionUsesHardwareDecoder(_ session: VTDecompressionSession) -> Bool {
        var propertyValue: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &propertyValue) { propertyValuePointer in
            VTSessionCopyProperty(
                session,
                key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                allocator: kCFAllocatorDefault,
                valueOut: propertyValuePointer
            )
        }
        guard status == noErr, let propertyValue else {
            return false
        }

        return CFBooleanGetValue((propertyValue as! CFBoolean))
    }

    func rebuildFormatDescriptionIfNeeded(for frameSubmission: VideoFrameSubmission) throws {
        guard MoonlightVideoFormat.isAV1(configuredVideoFormat) else {
            throw MetalRendererError.unsupportedVideoFormat(configuredVideoFormat)
        }
        guard MoonlightVideoFormat.isAV1Main8(configuredVideoFormat) else {
            throw MetalRendererError.unsupportedAV1Profile(configuredVideoFormat)
        }

        guard let sequenceHeader = frameSubmission.sequenceHeader else {
            if formatDescription != nil {
                return
            }
            throw MetalRendererError.missingAV1DecoderConfiguration
        }

        let incomingConfiguration: AV1DecoderConfiguration
        do {
            incomingConfiguration = try AV1Bitstream.makeDecoderConfiguration(from: sequenceHeader)
        } catch {
            throw MetalRendererError.invalidAV1DecoderConfiguration
        }

        guard incomingConfiguration.profile == 0,
              incomingConfiguration.bitDepth == 8,
              incomingConfiguration.chromaSubsamplingX == 1,
              incomingConfiguration.chromaSubsamplingY == 1 else {
            throw MetalRendererError.unsupportedAV1SequenceHeader
        }

        if decoderConfiguration == incomingConfiguration, formatDescription != nil {
            return
        }

        let sampleDescriptionAtoms: [NSString: NSData] = [
            "av1C": incomingConfiguration.codecConfigurationRecord as NSData
        ]
        let bitsPerComponentKey = "BitsPerComponent" as CFString
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_FormatName: "av01",
            kCMFormatDescriptionExtension_Depth: 24,
            bitsPerComponentKey: incomingConfiguration.bitDepth,
            kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
            kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,
            kCMFormatDescriptionExtension_FullRangeVideo: true,
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: sampleDescriptionAtoms
        ]

        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_AV1,
            width: Int32(incomingConfiguration.codedWidth),
            height: Int32(incomingConfiguration.codedHeight),
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )

        guard status == noErr, let videoDescription = description else {
            throw MetalRendererError.failedToCreateFormatDescription(status)
        }

        decoderConfiguration = incomingConfiguration
        formatDescription = videoDescription
        invalidateDecompressionSessionLocked()
    }

    func createCompressedSampleBuffer(
        frameSubmission: VideoFrameSubmission,
        formatDescription: CMVideoFormatDescription,
        frameRate: Int32,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        let frameData = frameSubmission.frameData
        let frameLength = frameData.length
        guard frameLength > 0 else {
            return nil
        }

        let retainedStorage = Unmanaged.passRetained(frameData)
        let memory = UnsafeMutableRawPointer(mutating: frameData.bytes)
        var blockBuffer: CMBlockBuffer?

        var blockSource = CMBlockBufferCustomBlockSource(
            version: kCMBlockBufferCustomBlockSourceVersion,
            AllocateBlock: nil,
            FreeBlock: { refCon, _, _ in
                guard let refCon else { return }
                Unmanaged<VideoFrameData>.fromOpaque(refCon).release()
            },
            refCon: retainedStorage.toOpaque()
        )

        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: memory,
            blockLength: frameLength,
            blockAllocator: nil,
            customBlockSource: &blockSource,
            offsetToData: 0,
            dataLength: frameLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, let blockBuffer else {
            retainedStorage.release()
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: frameRate > 0 ? CMTimeScale(frameRate) : 120),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = frameLength
        let sampleBufferStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleBufferStatus == noErr, let sampleBuffer else {
            return nil
        }

        return sampleBuffer
    }

    func presentationTime(for frameSubmission: VideoFrameSubmission) -> CMTime {
        if frameSubmission.presentationTimeUs > 0 {
            return CMTime(value: CMTimeValue(frameSubmission.presentationTimeUs), timescale: 1_000_000)
        }

        return CMTime(value: CMTimeValue(frameSubmission.rtpTimestamp), timescale: 90_000)
    }

    func prepareShaderPipelineIfNeeded(device: MTLDevice) {
        guard renderQueue.sync(execute: { self.renderPipelineState == nil }) else {
            return
        }

        do {
            let shaderLibrary = try loadShaderLibrary(device: device)
            guard let vertexFunction = shaderLibrary.makeFunction(name: "metalVideoVertex"),
                  let fragmentFunction = shaderLibrary.makeFunction(name: "metalVideoFragment") else {
                reportError("Metal shader functions missing")
                return
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = "MoonlightMetalVideoPipeline"
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            let renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            renderQueue.sync {
                self.renderPipelineState = renderPipelineState
            }
            self.shaderLibrary = shaderLibrary
            clearError("Metal shader")
        } catch {
            let shaderPath = shaderSourceURL()?.path ?? "missing"
            reportError("Metal shader pipeline failed: \(describeMetalError(error)) source=\(shaderPath)")
        }
    }

    func loadShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let shaderLibrary {
            return shaderLibrary
        }

        if let resourceBundle = PackageResourceBundle.coreTarget,
           let bundledLibrary = try? device.makeDefaultLibrary(bundle: resourceBundle) {
            return bundledLibrary
        }

        guard let shaderURL = shaderSourceURL() else {
            throw MetalRendererError.shaderResourceMissing
        }

        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        return try device.makeLibrary(source: shaderSource, options: nil)
    }

    func shaderSourceURL() -> URL? {
        if let shaderURL = PackageResourceBundle.coreTarget?.url(forResource: "MetalRendererShaders", withExtension: "metal") {
            return shaderURL
        }

        return PackageResourceBundle.coreTarget?.url(forResource: "MetalRendererShaders", withExtension: "metal", subdirectory: "Video")
    }

    @discardableResult
    func submitRender(
        pixelBuffer: CVPixelBuffer,
        drawable: CAMetalDrawable,
        completion: (@Sendable () -> Void)? = nil
    ) -> Bool {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
            reportError("Unexpected pixel format \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
            return false
        }

        requestRenderPrerequisiteRecoveryIfNeeded()

        guard let commandQueue,
              let renderPipelineState,
              let textureCache
        else {
            reportError("Metal render prerequisites unavailable: \(missingRenderPrerequisitesDescription())")
            return false
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor(for: drawable)
        else {
            reportError("Metal command submission unavailable")
            return false
        }

        guard let planeTextures = makeTextures(for: pixelBuffer, textureCache: textureCache) else {
            reportError("Failed to map CVPixelBuffer to Metal textures")
            return false
        }

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            reportError("Failed to create Metal render encoder")
            return false
        }

        renderEncoder.label = "MoonlightMetalVideoRenderEncoder"
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBytes(
            quadVertices,
            length: MemoryLayout<SIMD4<Float>>.stride * quadVertices.count,
            index: 0
        )
        renderEncoder.setFragmentTexture(planeTextures.lumaTexture, index: 0)
        renderEncoder.setFragmentTexture(planeTextures.chromaTexture, index: 1)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: quadVertices.count)
        renderEncoder.endEncoding()

        let inFlightResources = MetalInFlightResources(
            pixelBuffer: pixelBuffer,
            lumaTextureRef: planeTextures.lumaTextureRef,
            chromaTextureRef: planeTextures.chromaTextureRef
        )
        commandBuffer.addCompletedHandler { _ in
            _ = inFlightResources
            completion?()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    func currentRenderPassDescriptor(for drawable: CAMetalDrawable) -> MTLRenderPassDescriptor? {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        return renderPassDescriptor
    }

    func makeTextures(for pixelBuffer: CVPixelBuffer, textureCache: CVMetalTextureCache) -> MetalPlaneTextures? {
        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var lumaTextureRef: CVMetalTexture?
        let lumaStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            lumaWidth,
            lumaHeight,
            0,
            &lumaTextureRef
        )

        guard lumaStatus == kCVReturnSuccess,
              let lumaTextureRef,
              let lumaTexture = CVMetalTextureGetTexture(lumaTextureRef) else {
            return nil
        }

        var chromaTextureRef: CVMetalTexture?
        let chromaStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg8Unorm,
            chromaWidth,
            chromaHeight,
            1,
            &chromaTextureRef
        )

        guard chromaStatus == kCVReturnSuccess,
              let chromaTextureRef,
              let chromaTexture = CVMetalTextureGetTexture(chromaTextureRef) else {
            return nil
        }

        return MetalPlaneTextures(
            lumaTexture: lumaTexture,
            chromaTexture: chromaTexture,
            lumaTextureRef: lumaTextureRef,
            chromaTextureRef: chromaTextureRef
        )
    }

    func requestRenderPrerequisiteRecoveryIfNeeded() {
        guard commandQueue == nil || renderPipelineState == nil || textureCache == nil else {
            return
        }

        guard let hostView else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.installMetalSurfaceIfPossible(on: hostView)
            if let metalDevice = self.metalDevice, self.renderQueue.sync(execute: { self.renderPipelineState == nil }) {
                self.prepareShaderPipelineIfNeeded(device: metalDevice)
            }
        }
    }

    func nextDrawableIfAvailable() -> CAMetalDrawable? {
        requestRenderPrerequisiteRecoveryIfNeeded()

        guard let metalLayer else {
            reportError("Metal layer unavailable for drawable acquisition")
            return nil
        }

        guard let drawable = metalLayer.nextDrawable() else {
            return nil
        }

        return drawable
    }

    func missingRenderPrerequisitesDescription() -> String {
        var missing: [String] = []
        if commandQueue == nil {
            missing.append("commandQueue")
        }
        if renderPipelineState == nil {
            missing.append("renderPipelineState")
        }
        if textureCache == nil {
            missing.append("textureCache")
        }
        return missing.isEmpty ? "unknown" : missing.joined(separator: ", ")
    }

    func reportError(_ message: String) {
        let shouldReport = stateQueue.sync { () -> Bool in
            if lastReportedError == message {
                return false
            }
            lastReportedError = message
            return true
        }

        guard shouldReport else {
            return
        }

        onError?(message)
    }

    func clearError(_ prefix: String) {
        stateQueue.sync {
            guard let lastReportedError, lastReportedError.contains(prefix) else {
                return
            }
            self.lastReportedError = nil
        }
    }

    func describeMetalError(_ error: Error) -> String {
        let nsError = error as NSError
        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            return "\(nsError.localizedDescription) (\(failureReason))"
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            return "\(nsError.localizedDescription) (\(recoverySuggestion))"
        }
        return nsError.localizedDescription
    }

    @discardableResult
    func runOnMainSync<T: Sendable>(_ operation: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                operation()
            }
        } else {
            return DispatchQueue.main.sync {
                operation()
            }
        }
    }

}

private enum MetalRendererError: Error {
    case missingAV1DecoderConfiguration
    case invalidAV1DecoderConfiguration
    case unsupportedVideoFormat(Int32)
    case unsupportedAV1Profile(Int32)
    case unsupportedAV1SequenceHeader
    case hardwareDecodeUnavailable
    case hardwareDecoderRequirementNotMet
    case failedToCreateFormatDescription(OSStatus)
    case failedToCreateDecompressionSession(OSStatus)
    case shaderResourceMissing
}

extension MetalRendererError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAV1DecoderConfiguration:
            return "Missing AV1 decoder configuration from keyframe sequence header."
        case .invalidAV1DecoderConfiguration:
            return "Invalid AV1 decoder configuration."
        case let .unsupportedVideoFormat(videoFormat):
            return "Unsupported negotiated video format \(MoonlightVideoFormat.name(for: videoFormat))."
        case let .unsupportedAV1Profile(videoFormat):
            return "Expected fixed AV1 Main8 negotiation but got \(MoonlightVideoFormat.name(for: videoFormat))."
        case .unsupportedAV1SequenceHeader:
            return "Only 8-bit AV1 Main profile 4:2:0 streams are supported."
        case .hardwareDecodeUnavailable:
            return RuntimeSupport.av1HardwareDecodeRequirementMessage
        case .hardwareDecoderRequirementNotMet:
            return "VideoToolbox did not provide a hardware AV1 decoder session."
        case let .failedToCreateFormatDescription(status):
            return "Failed to create AV1 format description (status \(status))."
        case let .failedToCreateDecompressionSession(status):
            return "Failed to create VideoToolbox decompression session (status \(status))."
        case .shaderResourceMissing:
            return "Metal shader resource is missing."
        }
    }
}

private struct DecodedMetalFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTimeStamp: CMTime
}

extension DecodedMetalFrame: @unchecked Sendable {}

private struct MetalPlaneTextures {
    let lumaTexture: MTLTexture
    let chromaTexture: MTLTexture
    let lumaTextureRef: CVMetalTexture
    let chromaTextureRef: CVMetalTexture
}

private final class MetalInFlightResources {
    let pixelBuffer: CVPixelBuffer
    let lumaTextureRef: CVMetalTexture
    let chromaTextureRef: CVMetalTexture

    init(pixelBuffer: CVPixelBuffer, lumaTextureRef: CVMetalTexture, chromaTextureRef: CVMetalTexture) {
        self.pixelBuffer = pixelBuffer
        self.lumaTextureRef = lumaTextureRef
        self.chromaTextureRef = chromaTextureRef
    }
}

extension MetalInFlightResources: @unchecked Sendable {}
