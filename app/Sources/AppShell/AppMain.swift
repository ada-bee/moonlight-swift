import AppKit
import MoonlightCore

@main
final class AppMain: NSObject, NSApplicationDelegate {
    private var appDelegate: AppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppMain()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appDelegate = AppDelegate()
        appDelegate?.applicationDidFinishLaunching(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appDelegate?.applicationWillTerminate(notification)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appDelegate?.applicationShouldTerminate(sender) ?? .terminateNow
    }
}
