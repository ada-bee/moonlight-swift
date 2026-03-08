import AppKit
import MoonlightCore

@MainActor
final class StreamViewController: NSViewController {
    private let sessionController: SessionController
    private let rendererView = VideoRendererView(frame: .zero)

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        layoutViews()
        sessionController.attachRenderer(to: rendererView)
    }

    private func layoutViews() {
        rendererView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(rendererView)

        NSLayoutConstraint.activate([
            rendererView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rendererView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rendererView.topAnchor.constraint(equalTo: view.topAnchor),
            rendererView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
