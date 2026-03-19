import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AppCoordinator?

    private var pendingTerminationTimeout: DispatchWorkItem?
    private var isTerminationInProgress = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification

        if let iconURL = Bundle.main.url(forResource: "GameStream", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stopActiveSession()
    }

    @IBAction func performClose(_ sender: Any?) {
        _ = sender
        coordinator?.hideActiveStreamWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = sender

        coordinator?.handlePrimaryActivationRequest()

        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sessionController = coordinator?.activeSessionController else {
            return .terminateNow
        }

        guard sessionController.shouldDelayApplicationTermination else {
            sessionController.stop()
            return .terminateNow
        }

        guard !isTerminationInProgress else {
            return .terminateLater
        }

        isTerminationInProgress = true

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.isTerminationInProgress else {
                return
            }

            self.isTerminationInProgress = false
            self.pendingTerminationTimeout = nil
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        pendingTerminationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)

        sessionController.stopAndWait { [weak self] in
            guard let self, self.isTerminationInProgress else {
                return
            }

            self.pendingTerminationTimeout?.cancel()
            self.pendingTerminationTimeout = nil
            self.isTerminationInProgress = false
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}
