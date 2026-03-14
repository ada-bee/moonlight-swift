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

public final class VideoFrameData: @unchecked Sendable {
    fileprivate var slab: VideoFrameDataSlab?
    public let length: Int

    init(slab: VideoFrameDataSlab, length: Int) {
        self.slab = slab
        self.length = length
    }

    public var bytes: UnsafeRawPointer {
        guard let slab else {
            preconditionFailure("Video frame data accessed after release")
        }

        return UnsafeRawPointer(slab.bytes)
    }

    public func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        guard let slab else {
            preconditionFailure("Video frame data accessed after release")
        }

        return try body(UnsafeRawBufferPointer(start: slab.bytes, count: length))
    }

    fileprivate func takeRetainedSlab() -> VideoFrameDataSlab {
        guard let slab else {
            preconditionFailure("Video frame slab already retained")
        }

        self.slab = nil
        return slab
    }

    deinit {
        slab?.recycle()
    }
}

public struct VideoFrameSubmission: @unchecked Sendable {
    public var frameType: Int32
    public var presentationTimeUs: UInt64
    public var rtpTimestamp: UInt32
    public var frameData: VideoFrameData
    public var sequenceHeader: Data?
}

final class VideoFrameDataPool: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumReusableSlabCount: Int
    private var reusableSlabs: [VideoFrameDataSlab] = []

    init(maximumReusableSlabCount: Int) {
        self.maximumReusableSlabCount = max(maximumReusableSlabCount, 0)
    }

    func checkout(minimumCapacity: Int) -> VideoFrameDataSlab? {
        let minimumCapacity = max(minimumCapacity, 1)

        lock.lock()
        if let index = reusableSlabs.firstIndex(where: { $0.capacity >= minimumCapacity }) {
            let slab = reusableSlabs.remove(at: index)
            lock.unlock()
            return slab
        }
        lock.unlock()

        return VideoFrameDataSlab(capacity: minimumCapacity, pool: self)
    }

    fileprivate func recycle(_ slab: VideoFrameDataSlab) {
        lock.lock()
        defer { lock.unlock() }

        guard reusableSlabs.count < maximumReusableSlabCount else {
            return
        }

        reusableSlabs.append(slab)
    }
}

final class VideoFrameDataSlab {
    let bytes: UnsafeMutableRawPointer
    let capacity: Int
    private weak var pool: VideoFrameDataPool?

    init?(capacity: Int, pool: VideoFrameDataPool?) {
        guard capacity > 0, let bytes = malloc(capacity) else {
            return nil
        }

        self.bytes = bytes
        self.capacity = capacity
        self.pool = pool
    }

    func recycle() {
        pool?.recycle(self)
    }

    deinit {
        free(bytes)
    }
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
