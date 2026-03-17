import AppKit
import MoonlightCore

@MainActor
final class StreamViewController: NSViewController {
    private let sessionController: SessionController
    private let rendererView = VideoRendererView(frame: .zero)
    private let inputView: StreamInputView

    var onLocalCommandSuppressionChanged: ((Bool) -> Void)? {
        get { inputView.onLocalCommandSuppressionChanged }
        set { inputView.onLocalCommandSuppressionChanged = newValue }
    }

    var mouseMode: StreamMouseMode {
        inputView.mouseMode
    }

    init(sessionController: SessionController, mouseMode: StreamMouseMode) {
        self.sessionController = sessionController
        self.inputView = StreamInputView(sessionController: sessionController)
        super.init(nibName: nil, bundle: nil)
        self.inputView.mouseMode = mouseMode
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
    }

    func setMouseCaptureState(_ isActive: Bool) {
        inputView.setMouseCaptureState(isActive)
    }

    func setMouseMode(_ mouseMode: StreamMouseMode) {
        inputView.mouseMode = mouseMode
    }

    func releaseAllRemoteInputs() {
        inputView.releaseAllRemoteInputs()
    }

    func resetLocalInputState() {
        inputView.resetLocalInputState()
    }

    func handleWindowDidResignKey() {
        inputView.handleWindowDidResignKey()
    }
}
