import AppKit
import MoonlightCore

@MainActor
final class StreamViewController: NSViewController {
    enum MouseMode {
        case absolute
        case raw
    }

    private let sessionController: SessionController
    private let rendererView = VideoRendererView(frame: .zero)
    private let inputView: StreamInputView

    var onLocalCommandSuppressionChanged: ((Bool) -> Void)? {
        get { inputView.onLocalCommandSuppressionChanged }
        set { inputView.onLocalCommandSuppressionChanged = newValue }
    }

    init(sessionController: SessionController, mouseMode: MouseMode) {
        self.sessionController = sessionController
        self.inputView = StreamInputView(sessionController: sessionController)
        super.init(nibName: nil, bundle: nil)
        self.inputView.mouseMode = mouseMode == .raw ? .raw : .absolute
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

    func setMouseCaptureActive(_ isActive: Bool) {
        inputView.isMouseCaptureActive = isActive
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
