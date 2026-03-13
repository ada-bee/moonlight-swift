import AppKit
import MoonlightCore

@MainActor
final class StreamViewController: NSViewController {
    private let sessionController: SessionController
    private let rendererView = VideoRendererView(frame: .zero)
    private let inputView: StreamInputView

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        self.inputView = StreamInputView(sessionController: sessionController)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        layoutViews()
        sessionController.attachRenderer(to: rendererView)
    }

    private func layoutViews() {
        inputView.rendererView = rendererView
    }

    func setFullscreenPresentation(_ isFullscreen: Bool) {
        inputView.setFullscreenPresentation(isFullscreen)
        inputView.isFullscreenPointerCaptureEnabled = isFullscreen
    }

    func releaseAllRemoteInputs() {
        inputView.releaseAllRemoteInputs()
    }

    func handleWindowDidResignKey() {
        inputView.handleWindowDidResignKey()
    }
}
