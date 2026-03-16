import Combine
import Foundation
import MoonlightCore

@MainActor
final class MainWindowModel: ObservableObject {
    enum MainContentState: Equatable {
        case loading
        case library
        case noHostConfigured
        case connectionIssue
    }

    @Published var hostInput = ""
    @Published private(set) var hasPairedHost = false
    @Published private(set) var hasConfiguredHost = false
    @Published private(set) var hasCompletedStartupLoad = false
    @Published private(set) var pairingInProgress = false
    @Published private(set) var pairingStatusText: String?
    @Published private(set) var pairingPIN: String?
    @Published private(set) var pairingError: String?
    @Published private(set) var libraryLoading = false
    @Published private(set) var hasLoadedLibrary = false
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

    func retryConnection() {
        coordinator.retryConnection()
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

    func usesRawMouse(for applicationID: Int) -> Bool {
        launchPreferences(for: applicationID).usesRawMouse
    }

    func windowedResolution(for applicationID: Int) -> MVPConfiguration.Video.Resolution {
        launchPreferences(for: applicationID).windowedResolution
    }

    func windowedFPS(for applicationID: Int) -> Int {
        launchPreferences(for: applicationID).windowedFPS
    }

    func setLaunchesFullscreen(_ launchesFullscreen: Bool, for applicationID: Int) {
        coordinator.setLaunchesFullscreen(launchesFullscreen, for: applicationID)
    }

    func setUsesRawMouse(_ usesRawMouse: Bool, for applicationID: Int) {
        coordinator.setUsesRawMouse(usesRawMouse, for: applicationID)
    }

    func setWindowedDisplayMode(_ resolution: MVPConfiguration.Video.Resolution, fps: Int, for applicationID: Int) {
        coordinator.setWindowedDisplayMode(resolution, fps: fps, for: applicationID)
    }

    func setWindowedResolution(_ resolution: MVPConfiguration.Video.Resolution, for applicationID: Int) {
        coordinator.setWindowedResolution(resolution, for: applicationID)
    }

    func setWindowedFPS(_ fps: Int, for applicationID: Int) {
        coordinator.setWindowedFPS(fps, for: applicationID)
    }

    var supportedWindowedResolutions: [MVPConfiguration.Video.Resolution] {
        coordinator.settings.video.supportedResolutions
    }

    var mainContentState: MainContentState {
        if !hasCompletedStartupLoad {
            return .loading
        }

        if !hasConfiguredHost {
            return .noHostConfigured
        }

        if pairingInProgress || libraryLoading {
            return .loading
        }

        if hasLoadedLibrary {
            return .library
        }

        return .connectionIssue
    }

    private func bindCoordinator() {
        coordinator.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else {
                    return
                }

                self.hasConfiguredHost = settings.host != nil
                self.hostInput = settings.host?.displayString ?? ""

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
                self?.hasPairedHost = record != nil
            }
            .store(in: &cancellables)

        coordinator.$hasCompletedStartupLoad
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasCompletedStartupLoad)

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
                    self.hasLoadedLibrary = false
                    self.libraryError = nil
                    self.applications = []
                case .loading:
                    self.libraryLoading = true
                    self.hasLoadedLibrary = false
                    self.libraryError = nil
                    self.applications = []
                case let .loaded(applications):
                    self.libraryLoading = false
                    self.hasLoadedLibrary = true
                    self.libraryError = nil
                    self.applications = applications
                case let .failed(message):
                    self.libraryLoading = false
                    self.hasLoadedLibrary = false
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
