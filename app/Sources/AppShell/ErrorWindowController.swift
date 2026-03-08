import AppKit
import Combine
import MoonlightCore

@MainActor
final class ErrorWindowController: NSWindowController {
    private var cancellables: Set<AnyCancellable> = []

    init(sessionController: SessionController) {
        let viewController = ErrorViewController(sessionController: sessionController)
        let window = NSWindow(contentViewController: viewController)
        window.title = "Connection Errors"
        window.setContentSize(NSSize(width: 520, height: 220))
        window.contentMinSize = NSSize(width: 420, height: 180)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        sessionController.$lastErrorDescription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self, let message, !message.isEmpty else {
                    return
                }
                self.showWindow(nil)
                self.window?.orderFrontRegardless()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class ErrorViewController: NSViewController {
    private let sessionController: SessionController
    private let textView = NSTextView(frame: .zero)
    private var cancellables: Set<AnyCancellable> = []

    init(sessionController: SessionController) {
        self.sessionController = sessionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1.0).cgColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        textView.string = "No errors."

        scrollView.documentView = textView
        root.addSubview(scrollView)
        view = root

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sessionController.$lastErrorDescription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.textView.string = message?.isEmpty == false ? message! : "No errors."
            }
            .store(in: &cancellables)
    }
}
