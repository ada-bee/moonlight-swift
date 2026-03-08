import AppKit
import MoonlightCore

@MainActor
final class AppDelegate: NSObject {
    private let configLoader = ConfigLoader()
    private var windowController: StreamWindowController?
    private var errorWindowController: ErrorWindowController?
    private var pendingTerminationTimeout: DispatchWorkItem?
    private var isTerminationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration: MVPConfiguration
        do {
            configuration = try configLoader.load()
        } catch {
            configuration = configLoader.fallbackForRuntime()
        }

        let sessionController = SessionController(configuration: configuration)
        let errorWindowController = ErrorWindowController(sessionController: sessionController)
        self.errorWindowController = errorWindowController

        let windowController = StreamWindowController(sessionController: sessionController)
        self.windowController = windowController
        windowController.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
        sessionController.autoConnectIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.sessionController.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sessionController = windowController?.sessionController else {
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
