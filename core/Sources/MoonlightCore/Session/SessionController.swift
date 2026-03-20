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

    public enum MouseButton: Int32 {
        case left = 0x01
        case middle = 0x02
        case right = 0x03
        case x1 = 0x04
        case x2 = 0x05
    }

    public enum MouseButtonAction: Int8 {
        case press = 0x07
        case release = 0x08
    }

    public enum KeyboardAction: Int8 {
        case down = 0x03
        case up = 0x04
    }

    public struct KeyboardModifiers: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let shift = KeyboardModifiers(rawValue: 0x01)
        public static let control = KeyboardModifiers(rawValue: 0x02)
        public static let alternate = KeyboardModifiers(rawValue: 0x04)
        public static let meta = KeyboardModifiers(rawValue: 0x08)
    }

    public struct KeyboardFlags: OptionSet, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let nonNormalized = KeyboardFlags(rawValue: 0x01)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var stageName: String = "Idle"
    @Published public private(set) var lastErrorDescription: String?

    public let configuration: StreamConfiguration
    public var onInputResetRequested: (@MainActor () -> Void)?

    private let bridge: MoonlightBridge
    private let renderer: VideoFrameRenderer
    private var activeStreamingActivity: NSObjectProtocol?

    public init(configuration: StreamConfiguration) {
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

        if let failureMessage = RuntimeSupport.currentStatus().failureMessage {
            endStreamingActivity()
            lastErrorDescription = failureMessage
            stageName = "Unsupported"
            state = .failed
            return
        }

        lastErrorDescription = nil
        stageName = "Connecting"
        state = .connecting
        beginStreamingActivity(reason: "Establishing stream connection...")

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

    public func sendRelativeMouse(deltaX: Int32, deltaY: Int32) {
        guard state == .streaming else {
            return
        }

        bridge.sendRelativeMouse(deltaX: Int16(clamping: deltaX), deltaY: Int16(clamping: deltaY))
    }

    public func sendAbsoluteMouse(x: Int32, y: Int32, referenceWidth: Int32, referenceHeight: Int32) {
        guard state == .streaming else {
            return
        }

        guard referenceWidth > 0, referenceHeight > 0 else {
            return
        }

        bridge.sendAbsoluteMouse(
            x: Int16(clamping: x),
            y: Int16(clamping: y),
            referenceWidth: Int16(clamping: referenceWidth),
            referenceHeight: Int16(clamping: referenceHeight)
        )
    }

    public func sendMouseButton(_ button: MouseButton, action: MouseButtonAction) {
        guard state == .streaming else {
            return
        }

        bridge.sendMouseButton(action: action.rawValue, button: button.rawValue)
    }

    public func sendScroll(delta: Int32) {
        guard state == .streaming else {
            return
        }

        bridge.sendHighResolutionScroll(delta: Int16(clamping: delta))
    }

    public func sendHorizontalScroll(delta: Int32) {
        guard state == .streaming else {
            return
        }

        bridge.sendHighResolutionHorizontalScroll(delta: Int16(clamping: delta))
    }

    public func sendKeyboard(
        virtualKey: UInt16,
        action: KeyboardAction,
        modifiers: KeyboardModifiers = [],
        flags: KeyboardFlags = []
    ) {
        guard state == .streaming else {
            return
        }

        bridge.sendKeyboard(
            keyCode: virtualKey,
            action: action.rawValue,
            modifiers: modifiers.rawValue,
            flags: flags.rawValue
        )
    }

    public func sendText(_ text: String) {
        guard state == .streaming else {
            return
        }

        bridge.sendText(text)
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

        requestInputReset()
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

    private func requestInputReset() {
        DispatchQueue.main.async {
            self.onInputResetRequested?()
        }
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
        requestInputReset()
        stageName = "Terminated"
        state = .stopped
        if errorCode != 0 {
            lastErrorDescription = "Stream terminated with code \(errorCode)"
        }
    }

    public func bridgeDidFailStage(_ name: String, errorCode: Int32) {
        endStreamingActivity()
        requestInputReset()
        stageName = name
        state = .failed
        lastErrorDescription = "Stage \(name) failed with code \(errorCode)"
    }
}
