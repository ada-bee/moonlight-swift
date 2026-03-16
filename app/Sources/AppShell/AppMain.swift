import AppKit
import SwiftUI

@main
struct AppMain: App {
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @StateObject private var mainWindowModel: MainWindowModel

    init() {
        let coordinator = AppCoordinator()
        _coordinator = StateObject(wrappedValue: coordinator)
        _mainWindowModel = StateObject(wrappedValue: MainWindowModel(coordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(model: mainWindowModel)
                .frame(minWidth: 960, minHeight: 560)
                .task {
                    appDelegate.coordinator = coordinator
                    coordinator.loadStartupState()
                    coordinator.setLibraryPollingActive(scenePhase == .active)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    coordinator.setLibraryPollingActive(newPhase == .active)
                }
        }
        .defaultSize(width: 1180, height: 720)

        Settings {
            SettingsView(coordinator: coordinator)
                .frame(minWidth: 520, minHeight: 680)
                .padding(24)
        }
        .defaultSize(width: 560, height: 760)
    }
}
