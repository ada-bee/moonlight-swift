import AppKit
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

    func resumeRunningApplication() {
        guard let runningApplication else {
            return
        }

        coordinator.launch(app: runningApplication)
    }

    func pauseRunningApplication() {
        guard let activeApplication else {
            return
        }

        coordinator.pauseStream(activeApplication)
    }

    func stopRunningApplication() {
        guard let runningApplication else {
            return
        }

        coordinator.stopRunningApplication(runningApplication)
    }

    func registerLibraryWindow(_ window: NSWindow?) {
        coordinator.setLibraryWindow(window)
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

    var runningApplication: HostApplication? {
        applications.first(where: { $0.isRunning })
    }

    var activeApplication: HostApplication? {
        guard let activeStreamApplicationID else {
            return nil
        }

        return applications.first(where: { $0.id == activeStreamApplicationID })
    }

    var hasRunningApplication: Bool {
        runningApplication != nil
    }

    var runningApplicationTitle: String {
        runningApplication?.name ?? "Nothing running"
    }

    var canResumeRunningApplication: Bool {
        guard let runningApplication else {
            return false
        }

        return !launchInProgress && !stopInProgress && activeStreamApplicationID != runningApplication.id
    }

    var canPauseRunningApplication: Bool {
        activeApplication != nil && !launchInProgress && !stopInProgress
    }

    var canStopRunningApplication: Bool {
        hasRunningApplication && !launchInProgress && !stopInProgress
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

}
