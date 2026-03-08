import AppKit
import MoonlightCore

final class StreamWindowController: NSWindowController {
    let sessionController: SessionController

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        let viewController = StreamViewController(sessionController: sessionController)
        let window = NSWindow(contentViewController: viewController)
        let resolution = sessionController.configuration.video.resolution
        let contentSize = NSSize(width: resolution.width, height: resolution.height)
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
}
