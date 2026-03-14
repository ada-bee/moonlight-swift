import AppKit
import CoreGraphics
import MoonlightCore

private final class StreamWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

final class StreamWindowController: NSWindowController, NSWindowDelegate {
    let sessionController: SessionController

    private let streamViewController: StreamViewController
    private let launchesFullscreen: Bool
    private let usesRawMouse: Bool
    private var rawMouseCaptureEnabled = false
    private var rawMouseCursorHidden = false
    private var localCommandSuppressionActive = false

    init(sessionController: SessionController, launchesFullscreen: Bool = false, usesRawMouse: Bool = false) {
        self.sessionController = sessionController
        self.launchesFullscreen = launchesFullscreen
        self.usesRawMouse = usesRawMouse
        self.streamViewController = StreamViewController(
            sessionController: sessionController,
            mouseMode: usesRawMouse ? .raw : .absolute
        )

        let contentRect = NSRect(origin: .zero, size: Self.streamContentSize(for: sessionController, screen: NSScreen.main))
        let window = StreamWindow(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = streamViewController
        window.collectionBehavior = [.fullScreenPrimary]
        window.acceptsMouseMovedEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.center()

        super.init(window: window)

        window.delegate = self
        streamViewController.onLocalCommandSuppressionChanged = { [weak self] isSuppressed in
            self?.setLocalCommandSuppressionActive(isSuppressed)
        }
        applyWindowSizing(isFullscreen: false)
        streamViewController.setFullscreenPresentation(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func resetToStreamResolution() {
        applyWindowSizing(isFullscreen: isFullscreen)
    }

    var isFullscreen: Bool {
        guard let window else {
            return false
        }

        return window.styleMask.contains(.fullScreen)
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func present() {
        showWindow(nil)

        guard launchesFullscreen, isFullscreen == false else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFullscreen == false else {
                return
            }

            self.window?.toggleFullScreen(nil)
        }
    }

    func releaseAllRemoteInputs() {
        streamViewController.releaseAllRemoteInputs()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        window?.makeFirstResponder(streamViewController.view)
        updateRawMouseCapture()
    }

    func windowDidResignKey(_ notification: Notification) {
        _ = notification
        disableRawMouseCaptureIfNeeded()
        streamViewController.handleWindowDidResignKey()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        _ = notification
        streamViewController.releaseAllRemoteInputs()
        streamViewController.setFullscreenPresentation(true)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        _ = notification
        applyWindowSizing(isFullscreen: true)
        window?.makeFirstResponder(streamViewController.view)
        updateRawMouseCapture()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        _ = notification
        streamViewController.releaseAllRemoteInputs()
        disableRawMouseCaptureIfNeeded()
        streamViewController.setFullscreenPresentation(false)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        _ = notification
        applyWindowSizing(isFullscreen: false)
        window?.makeFirstResponder(streamViewController.view)
        updateRawMouseCapture()
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        disableRawMouseCaptureIfNeeded()
        streamViewController.releaseAllRemoteInputs()
    }
}

private extension StreamWindowController {
    func updateRawMouseCapture() {
        guard !localCommandSuppressionActive else {
            disableRawMouseCaptureIfNeeded()
            return
        }

        if usesRawMouse {
            enableRawMouseCaptureIfNeeded()
        } else {
            disableRawMouseCaptureIfNeeded()
        }
    }

    func setLocalCommandSuppressionActive(_ isActive: Bool) {
        guard localCommandSuppressionActive != isActive else {
            return
        }

        localCommandSuppressionActive = isActive
        updateRawMouseCapture()
    }

    func enableRawMouseCaptureIfNeeded() {
        guard !rawMouseCaptureEnabled else {
            streamViewController.setMouseCaptureActive(true)
            return
        }

        guard NSApp.isActive, window?.isKeyWindow == true else {
            return
        }

        let associateResult = CGAssociateMouseAndMouseCursorPosition(0)
        guard associateResult == .success else {
            return
        }

        NSCursor.hide()
        rawMouseCursorHidden = true
        rawMouseCaptureEnabled = true
        streamViewController.setMouseCaptureActive(true)
    }

    func disableRawMouseCaptureIfNeeded() {
        guard rawMouseCaptureEnabled || rawMouseCursorHidden else {
            streamViewController.setMouseCaptureActive(false)
            return
        }

        _ = CGAssociateMouseAndMouseCursorPosition(1)

        if rawMouseCursorHidden {
            NSCursor.unhide()
        }

        rawMouseCursorHidden = false
        rawMouseCaptureEnabled = false
        streamViewController.setMouseCaptureActive(false)
    }

    func applyWindowSizing(isFullscreen: Bool) {
        guard let window else {
            return
        }

        if isFullscreen {
            window.contentMinSize = .zero
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            return
        }

        let contentSize = Self.streamContentSize(for: sessionController, screen: window.screen)
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
    }

    static func streamContentSize(for sessionController: SessionController, screen: NSScreen?) -> NSSize {
        let resolution = sessionController.configuration.video.resolution
        let backingScaleFactor = max(screen?.backingScaleFactor ?? 1.0, 1.0)
        return NSSize(
            width: CGFloat(resolution.width) / backingScaleFactor,
            height: CGFloat(resolution.height) / backingScaleFactor
        )
    }
}
