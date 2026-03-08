import AppKit
import SwiftUI

@main
struct AppMain: App {
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
                .frame(minWidth: 760, minHeight: 560)
                .task {
                    appDelegate.coordinator = coordinator
                    coordinator.loadStartupState()
                }
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView(coordinator: coordinator)
                .frame(width: 420)
                .padding(24)
        }
    }
}
