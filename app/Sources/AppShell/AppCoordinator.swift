import AppKit
import Combine
import Foundation
import MoonlightCore

@MainActor
final class AppCoordinator: ObservableObject {
    enum PairingState: Equatable {
        case idle
        case inProgress(status: String, pin: String?)
        case failed(String)
    }

    enum LibraryState: Equatable {
        case idle
        case loading
        case loaded([HostApplication])
        case failed(String)
    }

    @Published private(set) var settings: AppSettings = .initial
    @Published private(set) var pairedHost: PairedHostRecord?
    @Published private(set) var pairingState: PairingState = .idle
    @Published private(set) var libraryState: LibraryState = .idle
    @Published private(set) var activeSessionController: SessionController?
    @Published private(set) var activeStreamWindowController: StreamWindowController?
    @Published private(set) var activeErrorWindowController: ErrorWindowController?
    @Published private(set) var launchInProgress = false
    @Published private(set) var isLibraryStale = false

    private let appSupportPaths: AppSupportPaths
    private let settingsStore: AppSettingsStore
    private let pairedHostStore: PairedHostStore
    private let pairingService: PairingService
    private let libraryClient: HostLibraryClient
    private let posterImageLoader: PosterImageLoader
    private var sessionObservers: Set<AnyCancellable> = []
    private var hasLoadedStartupState = false

    init(
        appSupportPaths: AppSupportPaths = AppSupportPaths(),
        settingsStore: AppSettingsStore = AppSettingsStore(),
        pairedHostStore: PairedHostStore = PairedHostStore(),
        pairingService: PairingService = PairingService(),
        libraryClient: HostLibraryClient = HostLibraryClient(),
        posterImageLoader: PosterImageLoader = PosterImageLoader()
    ) {
        self.appSupportPaths = appSupportPaths
        self.settingsStore = settingsStore
        self.pairedHostStore = pairedHostStore
        self.pairingService = pairingService
        self.libraryClient = libraryClient
        self.posterImageLoader = posterImageLoader
    }

    func loadStartupState() {
        guard !hasLoadedStartupState else {
            return
        }

        hasLoadedStartupState = true

        do {
            _ = try appSupportPaths.prepare()
            settings = try settingsStore.loadOrCreate()
            try consumePendingPairingResetIfNeeded()
            try reloadPairedHostState()
            refreshLibrary()
        } catch {
            pairingState = .failed(error.localizedDescription)
            libraryState = .idle
        }
    }

    func startPairing(hostInput: String) {
        do {
            let authority = try HostAuthority(parsing: hostInput)
            settings.host = authority
            try settingsStore.save(settings)
            let pin = Self.randomPIN()
            pairingState = .inProgress(status: "Connecting to \(authority.displayString)", pin: pin)

            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let result = try await self.pairingService.pair(
                        host: authority,
                        deviceName: "Moonlight",
                        pin: pin,
                        progress: { [weak self] status in
                            await MainActor.run {
                                guard let self else {
                                    return
                                }
                                self.pairingState = .inProgress(status: status, pin: pin)
                            }
                        }
                    )

                    try await MainActor.run {
                        try self.pairedHostStore.save(result: result)
                        self.pairedHost = result.record
                        self.settings.host = result.record.host
                        try self.settingsStore.save(self.settings)
                        self.pairingState = .idle
                        self.refreshLibrary(force: true)
                    }
                } catch {
                    await MainActor.run {
                        self.pairingState = .failed(error.localizedDescription)
                    }
                }
            }
        } catch {
            pairingState = .failed(error.localizedDescription)
        }
    }

    func refreshLibrary() {
        refreshLibrary(force: false)
    }

    func refreshLibrary(force: Bool) {
        guard pairedHost != nil else {
            libraryState = .idle
            return
        }

        libraryState = .loading

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                guard let artifacts = try self.pairedHostStore.loadCurrentArtifacts() else {
                    await MainActor.run {
                        self.libraryState = .failed("No paired host credentials were found.")
                    }
                    return
                }

                var applications = try await self.libraryClient.fetchApplications(using: artifacts)
                if force || self.isLibraryStale {
                    self.isLibraryStale = false
                }

                for index in applications.indices {
                    if let posterURL = await self.posterImageLoader.ensurePoster(for: applications[index], using: artifacts) {
                        applications[index].posterURL = posterURL
                    }
                }

                await MainActor.run {
                    self.libraryState = .loaded(applications)
                }
            } catch {
                await MainActor.run {
                    self.libraryState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func launch(app: HostApplication) {
        guard !launchInProgress else {
            return
        }

        let configuration: MVPConfiguration
        do {
            configuration = try settings.makeConfiguration(appID: app.id, autoConnectOnLaunch: false)
        } catch {
            pairingState = .failed(error.localizedDescription)
            return
        }

        launchInProgress = true

        let sessionController = SessionController(configuration: configuration)
        observe(sessionController)

        let errorWindowController = ErrorWindowController(sessionController: sessionController)
        let streamWindowController = StreamWindowController(sessionController: sessionController)

        activeSessionController = sessionController
        activeErrorWindowController = errorWindowController
        activeStreamWindowController = streamWindowController

        streamWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionController.connect()
    }

    func markPairingResetOnNextLaunch() {
        settings.pendingPairingResetOnNextLaunch = true

        do {
            try settingsStore.save(settings)
        } catch {
            pairingState = .failed(error.localizedDescription)
        }
    }

    func consumePendingPairingResetIfNeeded() throws {
        guard settings.pendingPairingResetOnNextLaunch else {
            return
        }

        try pairedHostStore.removeCurrent()
        try clearPosterCacheIfNeeded()

        settings.host = nil
        settings.pendingPairingResetOnNextLaunch = false
        try settingsStore.save(settings)

        pairedHost = nil
        pairingState = .idle
        libraryState = .idle
        isLibraryStale = false
    }

    func stopActiveSession() {
        activeSessionController?.stop()
    }

    private func reloadPairedHostState() throws {
        pairedHost = try pairedHostStore.loadCurrentRecord()
        pairingState = .idle
    }

    private func clearPosterCacheIfNeeded() throws {
        let fileManager = appSupportPaths.fileManager
        let posterCacheDirectoryURL = appSupportPaths.posterCacheDirectoryURL

        guard fileManager.fileExists(atPath: posterCacheDirectoryURL.path) else {
            return
        }

        try fileManager.removeItem(at: posterCacheDirectoryURL)
        try appSupportPaths.createDirectoryIfNeeded(posterCacheDirectoryURL)
    }

    private func observe(_ sessionController: SessionController) {
        sessionObservers.removeAll()

        sessionController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak sessionController] state in
                guard let self, let sessionController, self.activeSessionController === sessionController else {
                    return
                }

                switch state {
                case .idle, .connecting:
                    break
                case .streaming, .failed:
                    self.launchInProgress = false
                case .stopped:
                    self.launchInProgress = false
                    self.isLibraryStale = true
                }
            }
            .store(in: &sessionObservers)
    }

    private static func randomPIN() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}
