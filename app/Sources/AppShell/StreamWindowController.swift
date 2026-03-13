import AppKit
import MoonlightCore

final class StreamWindowController: NSWindowController {
    let sessionController: SessionController

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        let viewController = StreamViewController(sessionController: sessionController)
        let window = NSWindow(contentViewController: viewController)
        let contentSize = Self.streamContentSize(for: sessionController, screen: NSScreen.main)
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func resetToStreamResolution() {
        guard let window else {
            return
        }

        let contentSize = Self.streamContentSize(for: sessionController, screen: window.screen)
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
    }

    private static func streamContentSize(for sessionController: SessionController, screen: NSScreen?) -> NSSize {
        let resolution = sessionController.configuration.video.resolution
        let backingScaleFactor = max(screen?.backingScaleFactor ?? 1.0, 1.0)
        return NSSize(
            width: CGFloat(resolution.width) / backingScaleFactor,
            height: CGFloat(resolution.height) / backingScaleFactor
        )
    }
}
