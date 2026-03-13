import Combine
import Foundation
import MoonlightCore

@MainActor
final class MainWindowModel: ObservableObject {
    @Published var hostInput = ""
    @Published private(set) var isPaired = false
    @Published private(set) var pairingInProgress = false
    @Published private(set) var pairingStatusText: String?
    @Published private(set) var pairingPIN: String?
    @Published private(set) var pairingError: String?
    @Published private(set) var libraryLoading = false
    @Published private(set) var libraryError: String?
    @Published private(set) var applications: [HostApplication] = []
    @Published private(set) var launchInProgress = false
    @Published private(set) var stopInProgress = false
    @Published private(set) var libraryActionError: String?
    @Published private(set) var shouldRefreshLibrary = false
    @Published private(set) var gameLaunchPreferences: [Int: AppGameLaunchPreferences] = [:]
    @Published private(set) var activeStreamApplicationID: Int?

    let coordinator: AppCoordinator

    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        bindCoordinator()
    }

    func startPairing() {
        coordinator.startPairing(hostInput: hostInput)
    }

    func refreshLibrary() {
        coordinator.refreshLibrary()
    }

    func launch(_ application: HostApplication) {
        coordinator.launch(app: application)
    }

    func pause(_ application: HostApplication) {
        coordinator.pauseStream(application)
    }

    func stop(_ application: HostApplication) {
        coordinator.stopRunningApplication(application)
    }

    func launchesFullscreen(for applicationID: Int) -> Bool {
        launchPreferences(for: applicationID).launchesFullscreen
    }

    func windowedResolution(for applicationID: Int) -> MVPConfiguration.Video.Resolution {
        launchPreferences(for: applicationID).windowedResolution
    }

    func setLaunchesFullscreen(_ launchesFullscreen: Bool, for applicationID: Int) {
        coordinator.setLaunchesFullscreen(launchesFullscreen, for: applicationID)
    }

    func setWindowedResolution(_ resolution: MVPConfiguration.Video.Resolution, for applicationID: Int) {
        coordinator.setWindowedResolution(resolution, for: applicationID)
    }

    private func bindCoordinator() {
        coordinator.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else {
                    return
                }

                if let host = settings.host {
                    self.hostInput = host.displayString
                } else if self.hostInput.isEmpty {
                    self.hostInput = ""
                }

                var mappedPreferences: [Int: AppGameLaunchPreferences] = [:]
                for (applicationID, preferences) in settings.perGameLaunchPreferences {
                    if let numericID = Int(applicationID) {
                        mappedPreferences[numericID] = preferences
                    }
                }
                self.gameLaunchPreferences = mappedPreferences
            }
            .store(in: &cancellables)

        coordinator.$pairedHost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] record in
                self?.isPaired = record != nil
            }
            .store(in: &cancellables)

        coordinator.$pairingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else {
                    return
                }

                switch state {
                case .idle:
                    self.pairingInProgress = false
                    self.pairingStatusText = nil
                    self.pairingPIN = nil
                    self.pairingError = nil
                case let .inProgress(status, pin):
                    self.pairingInProgress = true
                    self.pairingStatusText = status
                    self.pairingPIN = pin
                    self.pairingError = nil
                case let .failed(message):
                    self.pairingInProgress = false
                    self.pairingStatusText = nil
                    self.pairingPIN = nil
                    self.pairingError = message
                }
            }
            .store(in: &cancellables)

        coordinator.$libraryState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else {
                    return
                }

                switch state {
                case .idle:
                    self.libraryLoading = false
                    self.libraryError = nil
                    self.applications = []
                case .loading:
                    self.libraryLoading = true
                    self.libraryError = nil
                    self.applications = []
                case let .loaded(applications):
                    self.libraryLoading = false
                    self.libraryError = nil
                    self.applications = applications
                case let .failed(message):
                    self.libraryLoading = false
                    self.libraryError = message
                    self.applications = []
                }
            }
            .store(in: &cancellables)

        coordinator.$launchInProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$launchInProgress)

        coordinator.$stopInProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$stopInProgress)

        coordinator.$libraryActionError
            .receive(on: DispatchQueue.main)
            .assign(to: &$libraryActionError)

        coordinator.$isLibraryStale
            .receive(on: DispatchQueue.main)
            .assign(to: &$shouldRefreshLibrary)

        coordinator.$activeSessionController
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionController in
                self?.activeStreamApplicationID = sessionController?.configuration.host.appID
            }
            .store(in: &cancellables)
    }

    private func launchPreferences(for applicationID: Int) -> AppGameLaunchPreferences {
        gameLaunchPreferences[applicationID] ?? coordinator.settings.launchPreferences(for: applicationID)
    }
}
