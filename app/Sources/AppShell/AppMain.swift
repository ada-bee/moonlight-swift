import AppKit
import SwiftUI

@main
struct AppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @State private var didStartCoordinator = false

    init() {
        let coordinator = AppCoordinator()
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
                .task {
                    guard !didStartCoordinator else {
                        return
                    }

                    didStartCoordinator = true
                    appDelegate.coordinator = coordinator
                    coordinator.loadStartupState()
                }
                .frame(minWidth: 320)
        } label: {
            MenuBarStatusIcon(streamActivityState: coordinator.streamActivityState)
        }
        .menuBarExtraStyle(.window)
        .commands {
            StreamCommands(coordinator: coordinator)
        }

        Settings {
            SettingsView(coordinator: coordinator)
                .frame(minWidth: 620, minHeight: 700)
        }
        .defaultSize(width: 680, height: 760)
    }
}
