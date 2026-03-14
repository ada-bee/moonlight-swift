import AppKit
import Foundation

public protocol VideoFrameRenderer: AnyObject {
    var rendererName: String { get }
    var onError: (@Sendable (String) -> Void)? { get set }
    func attach(to hostView: VideoRendererView)
    func configure(videoFormat: Int32, width: Int32, height: Int32, redrawRate: Int32)
    func start()
    func stop()
    func cleanup()
    func submit(frameSubmission: VideoFrameSubmission) -> Int32
}

public struct VideoFrameSubmission: @unchecked Sendable {
    public var frameType: Int32
    public var presentationTimeUs: UInt64
    public var rtpTimestamp: UInt32
    public var frameData: NSData
    public var sequenceHeader: Data?
}

public final class VideoRendererView: NSView {
    public var onLayout: ((CGRect) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    public override func layout() {
        super.layout()
        onLayout?(bounds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
