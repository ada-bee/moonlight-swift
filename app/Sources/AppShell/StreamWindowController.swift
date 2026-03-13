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
    private var cursorCaptureEnabled = false
    private var cursorHidden = false

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        self.streamViewController = StreamViewController(sessionController: sessionController)

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

    func releaseAllRemoteInputs() {
        streamViewController.releaseAllRemoteInputs()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        window?.makeFirstResponder(streamViewController.view)
        if isFullscreen {
            enableCursorCaptureIfNeeded()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        _ = notification
        disableCursorCaptureIfNeeded()
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
        enableCursorCaptureIfNeeded()
        window?.makeFirstResponder(streamViewController.view)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        _ = notification
        streamViewController.releaseAllRemoteInputs()
        disableCursorCaptureIfNeeded()
        streamViewController.setFullscreenPresentation(false)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        _ = notification
        applyWindowSizing(isFullscreen: false)
        window?.makeFirstResponder(streamViewController.view)
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        disableCursorCaptureIfNeeded()
        streamViewController.releaseAllRemoteInputs()
    }
}

private extension StreamWindowController {
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

    func enableCursorCaptureIfNeeded() {
        guard !cursorCaptureEnabled else {
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
        cursorHidden = true
        cursorCaptureEnabled = true
    }

    func disableCursorCaptureIfNeeded() {
        guard cursorCaptureEnabled || cursorHidden else {
            return
        }

        _ = CGAssociateMouseAndMouseCursorPosition(1)

        if cursorHidden {
            NSCursor.unhide()
        }

        cursorHidden = false
        cursorCaptureEnabled = false
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
