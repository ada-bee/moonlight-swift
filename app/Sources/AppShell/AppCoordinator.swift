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

    enum HostAvailabilityState: Equatable {
        case unconfigured
        case checking
        case reachable
        case unreachable(String)
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
    @Published private(set) var activeErrorWindowController: ErrorWindowController?
    @Published private(set) var launchInProgress = false
    @Published private(set) var stopInProgress = false
    @Published private(set) var libraryActionError: String?
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
    private var hostStateRefreshTask: Task<Void, Never>?
    private var queuedHostStateRefresh = false
    private var libraryRefreshTask: Task<Void, Never>?
    private var queuedLibraryRefreshForce = false
    private var queuedLibraryRefreshShowsLoading = false
    private var isDockVisible = false

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

        setDockVisibility(false)

        do {
            _ = try appSupportPaths.prepare()
            settings = try settingsStore.loadOrCreate()
            currentRunningApplicationID = 0
            try consumePendingPairingResetIfNeeded()
            try reloadPairedHostState()
            sendWakeOnLANOnLaunchIfConfigured()
            refreshLibrary()
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

    func menuBarDidOpen() {
        scheduleHostStateRefresh()
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
                    self.libraryActionError = nil
                    self.scheduleHostStateRefresh()
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

    func handlePrimaryActivationRequest() {
        if let activeStreamWindowController {
            if activeStreamWindowController.isWindowVisible {
                presentActiveStreamWindow()
                return
            }

            showExistingStreamWindow()
            return
        }

        if canResumeRunningApplication {
            resumeRunningApplication()
            return
        }

        if canLaunchDesktop {
            launchDesktop()
        }
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
            await self?.scheduleHostStateRefreshAfterEvent()
        }
    }

    func stopRunningApplication() {
        guard canStopRunningApplication else {
            return
        }

        stopRunningApplication(id: currentRunningApplicationID)
    }

    func presentActiveStreamWindow() {
        setDockVisibility(true)
        activeStreamWindowController?.present()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideActiveStreamWindow() {
        guard let activeStreamWindowController else {
            return
        }

        activeStreamWindowController.hideWindow()
        setDockVisibility(false)
    }

    func stopSessionAndHideWindow() {
        guard activeSessionController != nil || currentRunningApplicationID != 0 else {
            hideActiveStreamWindow()
            return
        }

        if canStopRunningApplication {
            stopRunningApplication()
            hideActiveStreamWindow()
            return
        }

        stopActiveSession()
        hideActiveStreamWindow()
    }

    func terminateApplication() {
        stopSessionAndHideWindow()
        NSApp.terminate(nil)
    }

    private func showExistingStreamWindow() {
        setDockVisibility(true)
        activeStreamWindowController?.present()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isErrorWindowVisible: Bool {
        activeErrorWindowController?.window?.isVisible == true
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

    var streamMode: StreamMode {
        settings.streamMode
    }

    var windowedStreamResolution: MVPConfiguration.Video.Resolution {
        settings.video.resolution
    }

    var windowedStreamFPS: Int {
        settings.video.fps
    }

    var currentStreamResolution: MVPConfiguration.Video.Resolution? {
        if let activeSessionController {
            return activeSessionController.configuration.video.resolution
        }

        guard currentRunningApplicationID != 0 else {
            return nil
        }

        return launchVideoMode(for: streamMode).resolution
    }

    var currentStreamFPS: Int? {
        if let activeSessionController {
            return activeSessionController.configuration.video.fps
        }

        guard currentRunningApplicationID != 0 else {
            return nil
        }

        return launchVideoMode(for: streamMode).fps
    }

    var hostAvailabilityState: HostAvailabilityState {
        guard pairedHost != nil else {
            return .unconfigured
        }

        switch libraryState {
        case .idle, .loading:
            return .checking
        case .loaded:
            return .reachable
        case let .failed(message):
            return .unreachable(message)
        }
    }

    var hasWakeOnLANConfiguration: Bool {
        pairedHost?.wakeOnLANConfiguration != nil
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

    func setStreamMode(_ mode: StreamMode) {
        guard !launchInProgress, !stopInProgress else {
            return
        }

        guard streamMode != mode else {
            return
        }

        do {
            try saveStreamMode(mode)
            reconnectActiveStreamIfNeeded()
        } catch {
            libraryActionError = error.localizedDescription
        }
    }

    func setWindowedStreamResolution(_ resolution: MVPConfiguration.Video.Resolution) {
        guard !launchInProgress, !stopInProgress else {
            return
        }

        guard windowedStreamResolution != resolution else {
            return
        }

        do {
            try saveWindowedVideoSettings(resolution: resolution, fps: windowedStreamFPS)
            reconnectActiveStreamIfNeeded(onlyWhenWindowed: true)
        } catch {
            libraryActionError = error.localizedDescription
        }
    }

    func setWindowedStreamFPS(_ fps: Int) {
        guard !launchInProgress, !stopInProgress else {
            return
        }

        guard windowedStreamFPS != fps else {
            return
        }

        do {
            try saveWindowedVideoSettings(resolution: windowedStreamResolution, fps: fps)
            reconnectActiveStreamIfNeeded(onlyWhenWindowed: true)
        } catch {
            libraryActionError = error.localizedDescription
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

    func saveSupportedResolutions(_ resolutions: [MVPConfiguration.Video.Resolution]) throws {
        var updatedSettings = settings
        let normalizedResolutions = AppSettings.Video.normalizedSupportedResolutions(resolutions)
        updatedSettings.video.supportedResolutions = normalizedResolutions

        let defaultResolution = MVPConfiguration.Video.Resolution(
            width: updatedSettings.video.resolution.width,
            height: updatedSettings.video.resolution.height
        )
        if normalizedResolutions.contains(defaultResolution) == false,
           let fallbackResolution = normalizedResolutions.first
        {
            updatedSettings.video.resolution = fallbackResolution
        }

        try persistSettings(updatedSettings)
    }

    func saveWindowedVideoSettings(
        resolution: MVPConfiguration.Video.Resolution,
        fps: Int
    ) throws {
        var updatedSettings = settings

        if updatedSettings.video.supportedResolutions.contains(resolution) == false {
            updatedSettings.video.supportedResolutions = AppSettings.Video.normalizedSupportedResolutions(
                updatedSettings.video.supportedResolutions + [resolution]
            )
        }

        updatedSettings.video.resolution = resolution
        updatedSettings.video.fps = fps

        try persistSettings(updatedSettings)
    }

    func resetPairing() async throws {
        libraryRefreshTask?.cancel()
        libraryRefreshTask = nil
        hostStateRefreshTask?.cancel()
        hostStateRefreshTask = nil
        queuedHostStateRefresh = false
        queuedLibraryRefreshForce = false
        queuedLibraryRefreshShowsLoading = false

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
        currentRunningApplicationID = 0
    }

    func stopActiveSession() {
        Task { [weak self] in
            await self?.teardownActiveSession(closeErrorWindow: true)
        }
    }

    var canHideActiveStreamWindow: Bool {
        activeStreamWindowController?.isWindowVisible == true
    }

    var canStopSessionAndHideWindow: Bool {
        activeSessionController != nil || currentRunningApplicationID != 0
    }

    func sendWakeOnLANMagicPacket() {
        guard let configuration = pairedHost?.wakeOnLANConfiguration else {
            libraryActionError = "Wake-on-LAN is not configured for this host."
            return
        }

        libraryActionError = nil

        let wakeOnLANClient = wakeOnLANClient
        Task { [weak self] in
            do {
                try await Self.sendWakeOnLANMagicPacketRetries(
                    using: wakeOnLANClient,
                    configuration: configuration
                )

                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    self?.refreshLibraryAfterWakeOnLAN()
                }
            } catch {
                await MainActor.run {
                    self?.recordWakeOnLANError(error)
                }
            }
        }
    }

    private func refreshLibraryAfterWakeOnLAN() {
        refreshLibrary(force: true, showLoadingIndicator: false)
    }

    private func recordWakeOnLANError(_ error: Error) {
        libraryActionError = error.localizedDescription
    }

    private static func sendWakeOnLANMagicPacketRetries(
        using wakeOnLANClient: WakeOnLANClient,
        configuration: WakeOnLANConfiguration
    ) async throws {
        try await Task.detached(priority: .utility) {
            for attempt in 0..<3 {
                try wakeOnLANClient.sendMagicPacket(configuration: configuration)

                guard attempt < 2 else {
                    continue
                }

                try await Task.sleep(nanoseconds: 350_000_000)
            }
        }.value
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

                let streamMode = await MainActor.run { self.streamMode }
                let requestedVideoMode = await MainActor.run { self.launchVideoMode(for: streamMode) }
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
                        launchesFullscreen: streamMode == .fullscreen
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
                        self.activeStreamWindowController?.closeWindow()
                        self.activeStreamWindowController = nil
                        self.setDockVisibility(false)
                    }
                    self.scheduleHostStateRefresh()
                case .stopped:
                    self.launchInProgress = false
                    self.activeSessionController = nil
                    self.activeStreamWindowController?.closeWindow()
                    self.activeStreamWindowController = nil
                    self.setDockVisibility(false)
                    self.scheduleHostStateRefresh()
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

    private func scheduleHostStateRefresh() {
        guard pairedHost != nil else {
            return
        }

        if hostStateRefreshTask != nil {
            queuedHostStateRefresh = true
            return
        }

        hostStateRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshHostState()
            self.hostStateRefreshTask = nil

            if self.queuedHostStateRefresh {
                self.queuedHostStateRefresh = false
                self.scheduleHostStateRefresh()
            }
        }
    }

    private func scheduleHostStateRefreshAfterEvent() async {
        guard pairedHost != nil else {
            return
        }

        if let hostStateRefreshTask {
            queuedHostStateRefresh = true
            await hostStateRefreshTask.value
            return
        }

        await refreshHostState()
    }

    private func refreshHostState() async {
        guard pairedHost != nil else {
            return
        }

        do {
            guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
                return
            }

            let runningStatus = try await libraryClient.fetchRunningStatus(using: artifacts)

            guard !Task.isCancelled else {
                return
            }

            applyRunningStatus(runningStatus)

            if shouldRefreshLibrary(for: runningStatus.currentApplicationID) {
                refreshLibrary(force: true, showLoadingIndicator: false)
            }
        } catch {
        }
    }

    private func shouldRefreshLibrary(for runningApplicationID: Int) -> Bool {
        guard case let .loaded(applications) = libraryState else {
            return true
        }

        guard runningApplicationID != 0 else {
            return false
        }

        return applications.contains(where: { $0.id == runningApplicationID }) == false
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

    private func launchVideoMode(for mode: StreamMode) -> (resolution: MVPConfiguration.Video.Resolution, fps: Int) {
        if mode == .fullscreen,
           let mainScreen = NSScreen.main
        {
            let frame = mainScreen.frame
            let scale = max(mainScreen.backingScaleFactor, 1.0)
            return (
                resolution: MVPConfiguration.Video.Resolution(
                    width: Int(frame.width * scale),
                    height: Int(frame.height * scale)
                ),
                fps: nativeRefreshRate(for: mainScreen) ?? windowedStreamFPS
            )
        }

        return (resolution: windowedStreamResolution, fps: windowedStreamFPS)
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

    private func saveStreamMode(_ mode: StreamMode) throws {
        var updatedSettings = settings
        updatedSettings.streamMode = mode
        try persistSettings(updatedSettings)
    }

    private func reconnectActiveStreamIfNeeded(onlyWhenWindowed: Bool = false) {
        guard let applicationID = activeStreamApplicationID else {
            return
        }

        if onlyWhenWindowed, streamMode != .windowed {
            return
        }

        reconnectActiveStream(for: applicationID)
    }

    private func persistSettings(_ updatedSettings: AppSettings) throws {
        try settingsStore.save(updatedSettings)
        settings = updatedSettings
        libraryActionError = nil
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

                let requestedVideoMode = await MainActor.run {
                    self.launchVideoMode(for: self.streamMode)
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
                        launchesFullscreen: self.streamMode == .fullscreen
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
        launchesFullscreen: Bool
    ) {
        launchInProgress = true

        activeErrorWindowController?.close()
        activeStreamWindowController?.close()

        let sessionController = SessionController(configuration: configuration)
        observe(sessionController)

        let errorWindowController = ErrorWindowController(sessionController: sessionController)
        let streamWindowController = StreamWindowController(
            sessionController: sessionController,
            launchesFullscreen: launchesFullscreen
        )
        sessionController.onInputResetRequested = { [weak streamWindowController] in
            streamWindowController?.resetLocalInputState()
        }
        errorWindowController.onVisibilityChange = { [weak self] isVisible in
            guard let self else {
                return
            }

            if isVisible {
                self.setDockVisibility(true)
            } else if self.activeStreamWindowController?.isWindowVisible != true {
                self.setDockVisibility(false)
            }
        }
        streamWindowController.onVisibilityChange = { [weak self, weak streamWindowController] isVisible in
            guard let self else {
                return
            }

            if isVisible {
                self.setDockVisibility(true)
            } else if self.activeStreamWindowController === streamWindowController,
                      !self.isErrorWindowVisible {
                self.setDockVisibility(false)
            }
        }
        streamWindowController.onCloseRequest = { [weak self] in
            self?.hideActiveStreamWindow()
        }
        streamWindowController.onStopAndCloseRequest = { [weak self] in
            self?.stopSessionAndHideWindow()
        }
        streamWindowController.onQuitRequest = { [weak self] in
            self?.terminateApplication()
        }

        activeSessionController = sessionController
        activeErrorWindowController = errorWindowController
        activeStreamWindowController = streamWindowController

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
        }
    }

    private func teardownActiveSession(closeErrorWindow: Bool) async {
        let sessionController = activeSessionController
        let streamWindowController = activeStreamWindowController
        let errorWindowController = activeErrorWindowController

        activeSessionController = nil
        activeStreamWindowController = nil
        if closeErrorWindow {
            activeErrorWindowController = nil
        }
        sessionObservers.removeAll()

        setDockVisibility(false)

        streamWindowController?.closeWindow()
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

    private func setDockVisibility(_ isVisible: Bool) {
        guard isDockVisible != isVisible else {
            return
        }

        let targetPolicy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        NSApp.setActivationPolicy(targetPolicy)
        isDockVisible = isVisible

        if isVisible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
