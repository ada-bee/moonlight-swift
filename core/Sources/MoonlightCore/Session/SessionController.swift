import AppKit
import Combine
import Foundation

public final class SessionController: NSObject, ObservableObject {
    public enum State: String {
        case idle
        case connecting
        case streaming
        case failed
        case stopped
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var stageName: String = "Idle"
    @Published public private(set) var lastErrorDescription: String?

    public let configuration: MVPConfiguration

    private let bridge: MoonlightBridge
    private let renderer: VideoFrameRenderer
    private var activeStreamingActivity: NSObjectProtocol?

    public init(configuration: MVPConfiguration) {
        self.configuration = configuration
        self.renderer = MetalVideoRenderer()
        self.bridge = MoonlightBridge(configuration: configuration, renderer: renderer)
        super.init()
        self.bridge.delegate = self
        self.renderer.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.lastErrorDescription = message
            }
        }
    }

    public func attachRenderer(to hostView: VideoRendererView) {
        renderer.attach(to: hostView)
    }

    public func autoConnectIfNeeded() {
        guard configuration.session.autoConnectOnLaunch else {
            return
        }
        connect()
    }

    public func connect() {
        guard state != .connecting else {
            return
        }

        lastErrorDescription = nil
        stageName = "Connecting"
        state = .connecting
        beginStreamingActivity(reason: "Establishing Moonlight stream")

        let bridge = self.bridge
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try bridge.startSync()
            } catch {
                DispatchQueue.main.async {
                    self.endStreamingActivity()
                    self.state = .failed
                    self.lastErrorDescription = error.localizedDescription
                }
            }
        }
    }

    public func stop() {
        stopAndWait {}
    }

    public var shouldDelayApplicationTermination: Bool {
        switch state {
        case .connecting, .streaming:
            return true
        case .idle, .failed, .stopped:
            return false
        }
    }

    public func stopAndWait(_ completion: @escaping @MainActor () -> Void) {
        let shouldStopBridge = shouldDelayApplicationTermination

        state = .stopped
        stageName = shouldStopBridge ? "Stopping" : "Stopped"
        endStreamingActivity()

        guard shouldStopBridge else {
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        let bridge = self.bridge
        DispatchQueue.global(qos: .userInitiated).async {
            bridge.stopSync()
            DispatchQueue.main.async {
                self.stageName = "Stopped"
                completion()
            }
        }
    }

    private func beginStreamingActivity(reason: String) {
        guard activeStreamingActivity == nil else {
            return
        }

        activeStreamingActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: reason
        )
    }

    private func endStreamingActivity() {
        guard let activeStreamingActivity else {
            return
        }

        ProcessInfo.processInfo.endActivity(activeStreamingActivity)
        self.activeStreamingActivity = nil
    }
}

extension SessionController: @unchecked Sendable {}

extension SessionController: MoonlightBridgeDelegate {
    public func bridgeDidChangeStage(_ name: String) {
        stageName = name
    }

    public func bridgeDidStartConnection() {
        stageName = "Streaming"
        state = .streaming
    }

    public func bridgeDidTerminateConnection(errorCode: Int32) {
        endStreamingActivity()
        stageName = "Terminated"
        state = .stopped
        if errorCode != 0 {
            lastErrorDescription = "Stream terminated with code \(errorCode)"
        }
    }

    public func bridgeDidFailStage(_ name: String, errorCode: Int32) {
        endStreamingActivity()
        stageName = name
        state = .failed
        lastErrorDescription = "Stage \(name) failed with code \(errorCode)"
    }
}
