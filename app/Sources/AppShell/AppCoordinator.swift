import AppKit
import Combine
import CoreGraphics
import Foundation
import MoonlightCore

@MainActor
final class AppCoordinator: ObservableObject {
    enum StreamActivityState {
        case inactive
        case paused
        case streaming
    }

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

    private enum ActiveStreamResumeError: LocalizedError {
        case noActiveStream
        case applicationNoLongerRunning

        var errorDescription: String? {
            switch self {
            case .noActiveStream:
                return "There is no active stream to reconnect."
            case .applicationNoLongerRunning:
                return "The host app is no longer running, so the stream could not be resumed."
            }
        }
    }

    @Published private(set) var settings: AppSettings = .initial
    @Published private(set) var pairedHost: PairedHostRecord?
    @Published private(set) var pairingState: PairingState = .idle
    @Published private(set) var libraryState: LibraryState = .idle
    @Published private(set) var activeSessionController: SessionController?
    @Published private(set) var activeStreamWindowController: StreamWindowController?
    @Published private(set) var activeStreamMouseMode: StreamMouseMode?
    @Published private(set) var activeErrorWindowController: ErrorWindowController?
    @Published private(set) var launchInProgress = false
    @Published private(set) var stopInProgress = false
    @Published private(set) var libraryActionError: String?
    @Published private(set) var isLibraryStale = false
    @Published private(set) var hasCompletedStartupLoad = false
    @Published private(set) var currentRunningApplicationID = 0

    private let appSupportPaths: AppSupportPaths
    private let settingsStore: AppSettingsStore
    private let pairedHostStore: PairedHostStore
    private let pairingService: PairingService
    private let libraryClient: HostLibraryClient
    private let wakeOnLANClient: WakeOnLANClient
    private var sessionObservers: Set<AnyCancellable> = []
    private var hasLoadedStartupState = false
    private var isLibraryPollingActive = false
    private var libraryPollingTask: Task<Void, Never>?
    private var libraryRefreshTask: Task<Void, Never>?
    private var queuedLibraryRefreshForce = false
    private var queuedLibraryRefreshShowsLoading = false
    private var pollsSinceLastBackgroundRefresh = 0

    private enum LibraryPollingDefaults {
        static let intervalNanoseconds: UInt64 = 3_000_000_000
        static let pollsPerApplicationRefresh = 10
    }

    private static let desktopApplicationID = MVPConfiguration.fallback.host.appID
    private static let desktopApplicationName = "Desktop"

    init(
        appSupportPaths: AppSupportPaths = AppSupportPaths(),
        settingsStore: AppSettingsStore = AppSettingsStore(),
        pairedHostStore: PairedHostStore = PairedHostStore(),
        pairingService: PairingService = PairingService(),
        libraryClient: HostLibraryClient = HostLibraryClient(),
        wakeOnLANClient: WakeOnLANClient = WakeOnLANClient()
    ) {
        self.appSupportPaths = appSupportPaths
        self.settingsStore = settingsStore
        self.pairedHostStore = pairedHostStore
        self.pairingService = pairingService
        self.libraryClient = libraryClient
        self.wakeOnLANClient = wakeOnLANClient
    }

    func loadStartupState() {
        guard !hasLoadedStartupState else {
            return
        }

        hasLoadedStartupState = true
        defer { hasCompletedStartupLoad = true }

        do {
            _ = try appSupportPaths.prepare()
            settings = try settingsStore.loadOrCreate()
            currentRunningApplicationID = 0
            try consumePendingPairingResetIfNeeded()
            try reloadPairedHostState()
            sendWakeOnLANOnLaunchIfConfigured()
            refreshLibrary()
            restartLibraryPollingIfNeeded()
        } catch {
            pairingState = .failed(error.localizedDescription)
            libraryState = .idle
        }
    }

    func startPairing(hostInput: String) {
        do {
            let authority = try HostAuthority(parsing: hostInput)
            let pin = Self.randomPIN()
            pairingState = .inProgress(status: "Connecting to \(authority.displayString)", pin: pin)

            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let result = try await self.pairingService.pair(
                        host: authority,
                        deviceName: "GameStream",
                        pin: pin,
                        skipVerifyCheck: true,
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
                        var record = result.record
                        if self.pairedHost?.host == record.host {
                            record.wakeOnLANConfiguration = self.pairedHost?.wakeOnLANConfiguration
                        }

                        try self.pairedHostStore.saveCurrent(
                            record: record,
                            clientCertificatePEM: result.identity.certificatePEM,
                            clientPrivateKeyPEM: result.identity.privateKeyPEM,
                            serverCertificatePEM: result.serverCertificatePEM
                        )
                        self.pairedHost = record
                        self.settings.host = record.host
                        try self.settingsStore.save(self.settings)
                        self.pairingState = .idle
                        self.refreshLibrary(force: true)
                        self.restartLibraryPollingIfNeeded()
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
        refreshLibrary(force: false, showLoadingIndicator: true)
    }

    func refreshLibrary(force: Bool) {
        refreshLibrary(force: force, showLoadingIndicator: true)
    }

    func setLibraryPollingActive(_ isActive: Bool) {
        isLibraryPollingActive = isActive

        if isActive {
            restartLibraryPollingIfNeeded()
        } else {
            stopLibraryPolling()
        }
    }

    private func stopRunningApplication(id applicationID: Int) {
        let shouldStopCurrentApplication = currentRunningApplicationID == applicationID
            || activeSessionController?.configuration.host.appID == applicationID
        guard shouldStopCurrentApplication, !stopInProgress, !launchInProgress else {
            return
        }

        libraryActionError = nil

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                if self.activeSessionController?.configuration.host.appID == applicationID {
                    await self.teardownActiveSession(closeErrorWindow: true)
                }

                try await self.stopHostApplication()

                await MainActor.run {
                    self.isLibraryStale = true
                    self.libraryActionError = nil
                    self.pollsSinceLastBackgroundRefresh = LibraryPollingDefaults.pollsPerApplicationRefresh
                }
            } catch {
                await MainActor.run {
                    self.libraryActionError = error.localizedDescription
                }
            }
        }
    }

    func launchDesktop() {
        launchApplication(id: Self.desktopApplicationID)
    }

    func resumeRunningApplication() {
        guard canResumeRunningApplication else {
            return
        }

        launchApplication(id: currentRunningApplicationID)
    }

    func pauseRunningApplication() {
        guard canPauseRunningApplication,
              activeStreamApplicationID != nil
        else {
            return
        }

        libraryActionError = nil

        Task { [weak self] in
            await self?.teardownActiveSession(closeErrorWindow: true)
        }
    }

    func stopRunningApplication() {
        guard canStopRunningApplication else {
            return
        }

        stopRunningApplication(id: currentRunningApplicationID)
    }

    func presentActiveStreamWindow() {
        activeStreamWindowController?.present()
        NSApp.activate(ignoringOtherApps: true)
    }

    var activeStreamApplicationID: Int? {
        activeSessionController?.configuration.host.appID
    }

    var streamActivityState: StreamActivityState {
        if activeStreamApplicationID != nil {
            return .streaming
        }

        if currentRunningApplicationID != 0 {
            return .paused
        }

        return .inactive
    }

    var hasRunningApplication: Bool {
        currentRunningApplicationID != 0
    }

    var runningApplicationTitle: String {
        guard currentRunningApplicationID != 0 else {
            return "Nothing running"
        }

        return displayName(for: currentRunningApplicationID)
    }

    var canLaunchDesktop: Bool {
        guard pairedHost != nil, !launchInProgress, !stopInProgress else {
            return false
        }

        if case .inProgress = pairingState {
            return false
        }

        return true
    }

    var canResumeRunningApplication: Bool {
        hasRunningApplication && !launchInProgress && !stopInProgress && activeStreamApplicationID == nil
    }

    var canPauseRunningApplication: Bool {
        activeStreamApplicationID != nil && !launchInProgress && !stopInProgress
    }

    var canStopRunningApplication: Bool {
        hasRunningApplication && !launchInProgress && !stopInProgress
    }

    var primaryActionTitle: String {
        switch streamActivityState {
        case .inactive:
            return "Launch Desktop"
        case .paused:
            if currentRunningApplicationID == Self.desktopApplicationID {
                return "Resume Desktop"
            }
            return "Launch Desktop"
        case .streaming:
            return activeStreamApplicationID == Self.desktopApplicationID ? "Show Desktop" : "Show Stream"
        }
    }

    var activeStreamScreenMode: StreamScreenMode? {
        guard let applicationID = activeStreamApplicationID else {
            return nil
        }

        return StreamScreenMode(launchesFullscreen: settings.launchPreferences(for: applicationID).launchesFullscreen)
    }

    var activeStreamResolution: MVPConfiguration.Video.Resolution? {
        guard let applicationID = activeStreamApplicationID else {
            return nil
        }

        return settings.launchPreferences(for: applicationID).windowedResolution
    }

    var activeStreamFPS: Int? {
        guard let applicationID = activeStreamApplicationID else {
            return nil
        }

        return settings.launchPreferences(for: applicationID).windowedFPS
    }

    var activeStreamSupportsResolutionSelection: Bool {
        activeStreamApplicationID != nil
    }

    func setActiveStreamScreenMode(_ screenMode: StreamScreenMode) {
        guard !launchInProgress, !stopInProgress,
              let applicationID = activeStreamApplicationID
        else {
            return
        }

        var preferences = settings.launchPreferences(for: applicationID)
        guard preferences.launchesFullscreen != screenMode.launchesFullscreen else {
            return
        }

        preferences.launchesFullscreen = screenMode.launchesFullscreen
        guard updateLaunchPreferences(preferences, for: applicationID) else {
            return
        }

        reconnectActiveStream(for: applicationID)
    }

    func setActiveStreamResolution(_ resolution: MVPConfiguration.Video.Resolution) {
        guard !launchInProgress, !stopInProgress,
              let applicationID = activeStreamApplicationID
        else {
            return
        }

        var preferences = settings.launchPreferences(for: applicationID)
        guard preferences.windowedResolution != resolution else {
            return
        }

        preferences.windowedResolution = resolution
        guard updateLaunchPreferences(preferences, for: applicationID) else {
            return
        }

        if !preferences.launchesFullscreen {
            reconnectActiveStream(for: applicationID)
        }
    }

    func setActiveStreamFPS(_ fps: Int) {
        guard !launchInProgress, !stopInProgress,
              let applicationID = activeStreamApplicationID
        else {
            return
        }

        var preferences = settings.launchPreferences(for: applicationID)
        guard preferences.windowedFPS != fps else {
            return
        }

        preferences.windowedFPS = fps
        guard updateLaunchPreferences(preferences, for: applicationID) else {
            return
        }

        if !preferences.launchesFullscreen {
            reconnectActiveStream(for: applicationID)
        }
    }

    private func refreshLibrary(force: Bool, showLoadingIndicator: Bool) {
        guard pairedHost != nil else {
            libraryState = .idle
            return
        }

        if libraryRefreshTask != nil {
            queuedLibraryRefreshForce = queuedLibraryRefreshForce || force
            queuedLibraryRefreshShowsLoading = queuedLibraryRefreshShowsLoading || showLoadingIndicator
            return
        }

        if showLoadingIndicator {
            libraryState = .loading
        }

        libraryRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                guard let artifacts = try self.pairedHostStore.loadCurrentArtifacts() else {
                    throw AppSettingsError.missingHost
                }

                let applications = try await self.libraryClient.fetchApplications(using: artifacts)
                let runningStatus = try await self.libraryClient.fetchRunningStatus(using: artifacts)

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.finishLibraryRefresh(
                        result: .success((applications, runningStatus)),
                        force: force,
                        showLoadingIndicator: showLoadingIndicator
                    )
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.finishLibraryRefresh(
                        result: .failure(error),
                        force: force,
                        showLoadingIndicator: showLoadingIndicator
                    )
                }
            }
        }
    }

    func setActiveStreamMouseMode(_ mouseMode: StreamMouseMode) {
        guard let streamWindowController = activeStreamWindowController,
              let applicationID = activeSessionController?.configuration.host.appID
        else {
            return
        }

        guard activeStreamMouseMode != mouseMode else {
            return
        }

        streamWindowController.setMouseMode(mouseMode)
        activeStreamMouseMode = mouseMode

        var preferences = settings.launchPreferences(for: applicationID)
        guard preferences.usesRawMouse != mouseMode.usesRawMouse else {
            return
        }

        preferences.usesRawMouse = mouseMode.usesRawMouse
        updateLaunchPreferences(preferences, for: applicationID)
    }

    func saveSupportedResolutions(_ resolutions: [MVPConfiguration.Video.Resolution]) throws {
        var updatedSettings = settings
        let normalizedResolutions = AppSettings.Video.normalizedSupportedResolutions(resolutions)
        updatedSettings.video.supportedResolutions = normalizedResolutions

        let defaultResolution = MVPConfiguration.Video.Resolution(
            width: updatedSettings.video.width,
            height: updatedSettings.video.height
        )
        if normalizedResolutions.contains(defaultResolution) == false,
           let fallbackResolution = normalizedResolutions.first
        {
            updatedSettings.video.width = fallbackResolution.width
            updatedSettings.video.height = fallbackResolution.height
        }

        try settingsStore.save(updatedSettings)
        settings = updatedSettings
    }

    func saveDefaultVideoSettings(
        resolution: MVPConfiguration.Video.Resolution,
        fps: Int
    ) throws {
        var updatedSettings = settings

        if updatedSettings.video.supportedResolutions.contains(resolution) == false {
            updatedSettings.video.supportedResolutions = AppSettings.Video.normalizedSupportedResolutions(
                updatedSettings.video.supportedResolutions + [resolution]
            )
        }

        updatedSettings.video.width = resolution.width
        updatedSettings.video.height = resolution.height
        updatedSettings.video.fps = fps

        try settingsStore.save(updatedSettings)
        settings = updatedSettings
    }

    func resetPairing() async throws {
        libraryRefreshTask?.cancel()
        libraryRefreshTask = nil
        queuedLibraryRefreshForce = false
        queuedLibraryRefreshShowsLoading = false

        stopLibraryPolling()
        await teardownActiveSession(closeErrorWindow: true)

        try pairedHostStore.removeCurrent()

        settings.host = nil
        settings.pendingPairingResetOnNextLaunch = false
        try settingsStore.save(settings)

        pairedHost = nil
        pairingState = .idle
        libraryState = .idle
        launchInProgress = false
        stopInProgress = false
        libraryActionError = nil
        isLibraryStale = false
        currentRunningApplicationID = 0
    }

    func saveWakeOnLANConfiguration(macAddress: String, broadcastAddress: String) throws {
        guard var record = pairedHost else {
            throw AppSettingsError.missingHost
        }

        guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
            throw AppSettingsError.missingHost
        }

        let normalizedConfiguration = try wakeOnLANClient.normalizedConfiguration(
            macAddress: macAddress,
            broadcastAddress: broadcastAddress
        )

        record.wakeOnLANConfiguration = normalizedConfiguration
        try pairedHostStore.saveCurrent(
            record: record,
            clientCertificatePEM: artifacts.clientCertificatePEM,
            clientPrivateKeyPEM: artifacts.clientPrivateKeyPEM,
            serverCertificatePEM: artifacts.serverCertificatePEM
        )
        pairedHost = record
    }

    func clearWakeOnLANConfiguration() throws {
        guard var record = pairedHost else {
            throw AppSettingsError.missingHost
        }

        guard record.wakeOnLANConfiguration != nil else {
            return
        }

        guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
            throw AppSettingsError.missingHost
        }

        record.wakeOnLANConfiguration = nil
        try pairedHostStore.saveCurrent(
            record: record,
            clientCertificatePEM: artifacts.clientCertificatePEM,
            clientPrivateKeyPEM: artifacts.clientPrivateKeyPEM,
            serverCertificatePEM: artifacts.serverCertificatePEM
        )
        pairedHost = record
    }

    func consumePendingPairingResetIfNeeded() throws {
        guard settings.pendingPairingResetOnNextLaunch else {
            return
        }

        try pairedHostStore.removeCurrent()

        settings.host = nil
        settings.pendingPairingResetOnNextLaunch = false
        try settingsStore.save(settings)

        pairedHost = nil
        pairingState = .idle
        libraryState = .idle
        stopInProgress = false
        libraryActionError = nil
        isLibraryStale = false
        currentRunningApplicationID = 0
        stopLibraryPolling()
    }

    func stopActiveSession() {
        Task { [weak self] in
            await self?.teardownActiveSession(closeErrorWindow: true)
        }
    }

    private func launchApplication(id applicationID: Int) {
        guard !launchInProgress, !stopInProgress else {
            return
        }

        if let failureMessage = RuntimeSupport.currentStatus().failureMessage {
            libraryActionError = failureMessage
            return
        }

        launchInProgress = true
        libraryActionError = nil

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let runningApplicationID = await self.currentRunningApplicationIDForLaunch()

                if let activeSessionController = await MainActor.run(body: { self.activeSessionController }),
                   activeSessionController.configuration.host.appID == applicationID,
                   await MainActor.run(body: { self.activeStreamWindowController != nil }),
                   (activeSessionController.state == .connecting || activeSessionController.state == .streaming)
                {
                    await MainActor.run {
                        self.presentActiveStreamWindow()
                        self.launchInProgress = false
                    }
                    return
                }

                if await MainActor.run(body: { self.activeSessionController != nil }) {
                    await self.teardownActiveSession(closeErrorWindow: true)
                }

                if runningApplicationID != 0, runningApplicationID != applicationID {
                    try await self.stopHostApplication()
                }

                let preferences = await MainActor.run { self.settings.launchPreferences(for: applicationID) }
                let requestedVideoMode = await MainActor.run { self.launchVideoMode(for: preferences) }
                let requestResume = runningApplicationID == applicationID
                let configuration = try await MainActor.run {
                    try self.settings.makeConfiguration(
                        appID: applicationID,
                        autoConnectOnLaunch: false,
                        requestResume: requestResume,
                        resolution: requestedVideoMode.resolution,
                        fps: requestedVideoMode.fps
                    )
                }

                await MainActor.run {
                    self.startSession(
                        configuration: configuration,
                        launchesFullscreen: preferences.launchesFullscreen,
                        usesRawMouse: preferences.usesRawMouse
                    )
                }
            } catch {
                await MainActor.run {
                    self.launchInProgress = false
                    self.libraryActionError = error.localizedDescription
                }
            }
        }
    }

    private func reloadPairedHostState() throws {
        pairedHost = try pairedHostStore.loadCurrentRecord()
        pairingState = .idle
    }

    private func sendWakeOnLANOnLaunchIfConfigured() {
        guard let configuration = pairedHost?.wakeOnLANConfiguration else {
            return
        }

        let wakeOnLANClient = wakeOnLANClient
        Task.detached(priority: .utility) {
            for attempt in 0..<3 {
                do {
                    try wakeOnLANClient.sendMagicPacket(configuration: configuration)
                } catch {
                    break
                }

                guard attempt < 2 else {
                    continue
                }

                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
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
                    if state == .failed {
                        self.activeSessionController = nil
                        self.activeStreamMouseMode = nil
                        self.activeStreamWindowController?.close()
                        self.activeStreamWindowController = nil
                    }
                case .stopped:
                    self.launchInProgress = false
                    self.isLibraryStale = true
                    self.activeSessionController = nil
                    self.activeStreamMouseMode = nil
                    self.activeStreamWindowController?.close()
                    self.activeStreamWindowController = nil
                }
            }
            .store(in: &sessionObservers)
    }

    private func finishLibraryRefresh(
        result: Result<([HostApplication], HostRunningStatus), Error>,
        force: Bool,
        showLoadingIndicator: Bool
    ) {
        libraryRefreshTask = nil

        switch result {
        case let .success((applications, runningStatus)):
            if force || isLibraryStale {
                isLibraryStale = false
            }

            if stopInProgress, runningStatus.currentApplicationID == 0 {
                stopInProgress = false
                libraryActionError = nil
            }

            currentRunningApplicationID = runningStatus.currentApplicationID
            libraryState = .loaded(applicationsMarkingRunning(applications, runningApplicationID: runningStatus.currentApplicationID))
        case let .failure(error):
            if showLoadingIndicator || !hasLoadedApplications {
                libraryState = .failed(error.localizedDescription)
            }
        }

        if queuedLibraryRefreshForce || queuedLibraryRefreshShowsLoading {
            let nextForce = queuedLibraryRefreshForce
            let nextShowLoading = queuedLibraryRefreshShowsLoading
            queuedLibraryRefreshForce = false
            queuedLibraryRefreshShowsLoading = false
            refreshLibrary(force: nextForce, showLoadingIndicator: nextShowLoading)
        }
    }

    private var hasLoadedApplications: Bool {
        if case .loaded = libraryState {
            return true
        }

        return false
    }

    private func applicationsMarkingRunning(_ applications: [HostApplication], runningApplicationID: Int) -> [HostApplication] {
        applications.map { application in
            var updated = application
            updated.isRunning = updated.id == runningApplicationID
            return updated
        }
    }

    private func applyRunningStatus(_ runningStatus: HostRunningStatus) {
        currentRunningApplicationID = runningStatus.currentApplicationID

        if stopInProgress, runningStatus.currentApplicationID == 0 {
            stopInProgress = false
            libraryActionError = nil
        }

        guard case let .loaded(applications) = libraryState else {
            return
        }

        let updatedApplications = applicationsMarkingRunning(applications, runningApplicationID: runningStatus.currentApplicationID)
        if updatedApplications != applications {
            libraryState = .loaded(updatedApplications)
        }
    }

    private func restartLibraryPollingIfNeeded() {
        guard isLibraryPollingActive, pairedHost != nil, libraryPollingTask == nil else {
            return
        }

        libraryPollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await self.pollRunningStatus()
                if Task.isCancelled {
                    break
                }

                self.pollsSinceLastBackgroundRefresh += 1
                if self.isLibraryStale || self.pollsSinceLastBackgroundRefresh >= LibraryPollingDefaults.pollsPerApplicationRefresh {
                    self.pollsSinceLastBackgroundRefresh = 0
                    self.refreshLibrary(force: true, showLoadingIndicator: false)
                }

                do {
                    try await Task.sleep(nanoseconds: LibraryPollingDefaults.intervalNanoseconds)
                } catch {
                    break
                }
            }

            await MainActor.run {
                self.libraryPollingTask = nil
            }
        }
    }

    private func stopLibraryPolling() {
        libraryPollingTask?.cancel()
        libraryPollingTask = nil
        pollsSinceLastBackgroundRefresh = 0
    }

    private func pollRunningStatus() async {
        guard pairedHost != nil else {
            return
        }

        do {
            guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
                return
            }

            let runningStatus = try await libraryClient.fetchRunningStatus(using: artifacts)
            await MainActor.run {
                self.applyRunningStatus(runningStatus)
            }
        } catch {
        }
    }

    private func currentRunningApplicationIDForLaunch() async -> Int {
        let cachedRunningApplicationID = currentRunningApplicationID

        guard let artifacts = try? pairedHostStore.loadCurrentArtifacts() else {
            return cachedRunningApplicationID
        }

        do {
            let runningStatus = try await libraryClient.fetchRunningStatus(using: artifacts)
            applyRunningStatus(runningStatus)
            return runningStatus.currentApplicationID
        } catch {
            return cachedRunningApplicationID
        }
    }

    private func launchVideoMode(for preferences: AppGameLaunchPreferences) -> (resolution: MVPConfiguration.Video.Resolution, fps: Int) {
        if preferences.launchesFullscreen,
           let mainScreen = NSScreen.main
        {
            let frame = mainScreen.frame
            let scale = max(mainScreen.backingScaleFactor, 1.0)
            return (
                resolution: MVPConfiguration.Video.Resolution(
                    width: Int(frame.width * scale),
                    height: Int(frame.height * scale)
                ),
                fps: nativeRefreshRate(for: mainScreen) ?? settings.video.fps
            )
        }

        return (resolution: preferences.windowedResolution, fps: preferences.windowedFPS)
    }

    private func nativeRefreshRate(for screen: NSScreen) -> Int? {
        if screen.maximumFramesPerSecond > 0 {
            return screen.maximumFramesPerSecond
        }

        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        guard let displayMode = CGDisplayCopyDisplayMode(CGDirectDisplayID(screenNumber.uint32Value)) else {
            return nil
        }

        let refreshRate = displayMode.refreshRate
        guard refreshRate > 0 else {
            return nil
        }

        return Int(refreshRate.rounded())
    }

    @discardableResult
    private func updateLaunchPreferences(_ preferences: AppGameLaunchPreferences, for applicationID: Int) -> Bool {
        settings.setLaunchPreferences(preferences, for: applicationID)

        do {
            try settingsStore.save(settings)
            libraryActionError = nil
            return true
        } catch {
            libraryActionError = error.localizedDescription
            return false
        }
    }

    private func reconnectActiveStream(for applicationID: Int) {
        guard activeSessionController != nil else {
            return
        }

        launchInProgress = true
        libraryActionError = nil

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                guard await MainActor.run(body: { self.activeSessionController?.configuration.host.appID == applicationID }) else {
                    throw ActiveStreamResumeError.noActiveStream
                }

                let preferences = await MainActor.run {
                    self.settings.launchPreferences(for: applicationID)
                }
                let requestedVideoMode = await MainActor.run {
                    self.launchVideoMode(for: preferences)
                }

                await self.teardownActiveSession(closeErrorWindow: true)

                let runningApplicationID = await self.currentRunningApplicationIDForLaunch()
                guard runningApplicationID == applicationID else {
                    throw ActiveStreamResumeError.applicationNoLongerRunning
                }

                let configuration = try await MainActor.run {
                    try self.settings.makeConfiguration(
                        appID: applicationID,
                        autoConnectOnLaunch: false,
                        requestResume: true,
                        resolution: requestedVideoMode.resolution,
                        fps: requestedVideoMode.fps
                    )
                }

                await MainActor.run {
                    self.startSession(
                        configuration: configuration,
                        launchesFullscreen: preferences.launchesFullscreen,
                        usesRawMouse: preferences.usesRawMouse
                    )
                }
            } catch {
                await MainActor.run {
                    self.launchInProgress = false
                    self.libraryActionError = error.localizedDescription
                }
            }
        }
    }

    private func startSession(
        configuration: MVPConfiguration,
        launchesFullscreen: Bool,
        usesRawMouse: Bool
    ) {
        launchInProgress = true

        activeErrorWindowController?.close()
        activeStreamWindowController?.close()

        let sessionController = SessionController(configuration: configuration)
        observe(sessionController)

        let errorWindowController = ErrorWindowController(sessionController: sessionController)
        let streamWindowController = StreamWindowController(
            sessionController: sessionController,
            launchesFullscreen: launchesFullscreen,
            usesRawMouse: usesRawMouse
        )
        sessionController.onInputResetRequested = { [weak streamWindowController] in
            streamWindowController?.resetLocalInputState()
        }

        activeSessionController = sessionController
        activeErrorWindowController = errorWindowController
        activeStreamWindowController = streamWindowController
        activeStreamMouseMode = streamWindowController.mouseMode

        streamWindowController.present()
        NSApp.activate(ignoringOtherApps: true)
        sessionController.connect()
    }

    private func stopHostApplication() async throws {
        guard !stopInProgress else {
            return
        }

        stopInProgress = true
        defer { stopInProgress = false }

        guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
            throw AppSettingsError.missingHost
        }

        try await libraryClient.stopRunningApplication(using: artifacts)
        await MainActor.run {
            self.applyRunningStatus(HostRunningStatus(currentApplicationID: 0))
            self.isLibraryStale = true
        }
    }

    private func teardownActiveSession(closeErrorWindow: Bool) async {
        let sessionController = activeSessionController
        let streamWindowController = activeStreamWindowController
        let errorWindowController = activeErrorWindowController

        activeSessionController = nil
        activeStreamWindowController = nil
        activeStreamMouseMode = nil
        if closeErrorWindow {
            activeErrorWindowController = nil
        }
        sessionObservers.removeAll()

        streamWindowController?.close()
        if closeErrorWindow {
            errorWindowController?.close()
        }

        guard let sessionController else {
            return
        }

        libraryActionError = nil

        await withCheckedContinuation { continuation in
            sessionController.stopAndWait {
                continuation.resume()
            }
        }
    }

    private static func randomPIN() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    private func displayName(for applicationID: Int) -> String {
        if applicationID == Self.desktopApplicationID {
            return Self.desktopApplicationName
        }

        if case let .loaded(applications) = libraryState,
           let application = applications.first(where: { $0.id == applicationID }) {
            return application.name
        }

        return "Running App"
    }
}
