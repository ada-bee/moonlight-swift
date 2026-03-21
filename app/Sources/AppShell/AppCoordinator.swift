import AppKit
import Combine
import CoreGraphics
import Foundation
import MoonlightCore

@MainActor
final class AppCoordinator: ObservableObject {
    enum MenuBarPopupState: Equatable {
        case offline
        case ready
        case paused
        case streaming
    }

    enum MenuBarPopupAction {
        case none
        case wakeUp
        case start
        case resume
        case pause
        case stop

        var dismissesPopup: Bool {
            switch self {
            case .start, .resume:
                return true
            case .none, .wakeUp, .pause, .stop:
                return false
            }
        }
    }

    struct MenuBarPopupButton {
        let title: String
        let systemImage: String?
        let action: MenuBarPopupAction
        let isEnabled: Bool
        let showsProgress: Bool
    }

    struct MenuBarPopupPresentation {
        let state: MenuBarPopupState
        let status: String
        let description: String
        let primaryButton: MenuBarPopupButton
        let secondaryButton: MenuBarPopupButton
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

    private enum HostReachabilityState: Equatable {
        case unknown
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
    @Published private(set) var wakeInProgress = false
    @Published private(set) var libraryActionError: String?
    @Published private(set) var hasCompletedStartupLoad = false
    @Published private(set) var currentRunningApplicationID = 0
    @Published private var hostReachabilityState: HostReachabilityState = .unknown

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
    private var wakeMonitoringTask: Task<Void, Never>?
    private var isDockVisible = false

    private static let desktopApplicationID = StreamConfiguration.fallback.host.appID
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
        if activeStreamWindowController != nil {
            presentActiveStreamWindow()
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

    private var isErrorWindowVisible: Bool {
        activeErrorWindowController?.window?.isVisible == true
    }

    var activeStreamApplicationID: Int? {
        activeSessionController?.configuration.host.appID
    }

    var menuBarPopupPresentation: MenuBarPopupPresentation {
        switch menuBarPopupState {
        case .offline:
            return .init(
                state: .offline,
                status: "Offline",
                description: offlineDescriptionText,
                primaryButton: offlinePrimaryButton,
                secondaryButton: disabledStopButton
            )
        case .ready:
            return .init(
                state: .ready,
                status: "Ready",
                description: configuredStreamInfoText,
                primaryButton: .init(
                    title: "Start",
                    systemImage: "play.fill",
                    action: .start,
                    isEnabled: canLaunchDesktop,
                    showsProgress: false
                ),
                secondaryButton: disabledStopButton
            )
        case .paused:
            return .init(
                state: .paused,
                status: "Paused",
                description: configuredStreamInfoText,
                primaryButton: .init(
                    title: "Resume",
                    systemImage: "play.fill",
                    action: .resume,
                    isEnabled: canResumeRunningApplication,
                    showsProgress: false
                ),
                secondaryButton: .init(
                    title: stopInProgress ? "Stopping..." : "Stop",
                    systemImage: stopInProgress ? nil : "stop.fill",
                    action: .stop,
                    isEnabled: canStopRunningApplication,
                    showsProgress: stopInProgress
                )
            )
        case .streaming:
            return .init(
                state: .streaming,
                status: "Streaming",
                description: configuredStreamInfoText,
                primaryButton: .init(
                    title: "Pause",
                    systemImage: "pause.fill",
                    action: .pause,
                    isEnabled: canPauseRunningApplication,
                    showsProgress: false
                ),
                secondaryButton: .init(
                    title: stopInProgress ? "Stopping..." : "Stop",
                    systemImage: stopInProgress ? nil : "stop.fill",
                    action: .stop,
                    isEnabled: canStopRunningApplication,
                    showsProgress: stopInProgress
                )
            )
        }
    }

    var hasRunningApplication: Bool {
        currentRunningApplicationID != 0
    }

    var selectedStreamPresetID: StreamPresetID {
        settings.selectedStreamPresetID
    }

    var selectedStreamPreset: AppSettings.StreamPreset {
        settings.selectedStreamPreset
    }

    var streamPresetIDs: [StreamPresetID] {
        StreamPresetID.allCases
    }

    func streamPreset(for id: StreamPresetID) -> AppSettings.StreamPreset {
        settings.video.preset(id)
    }

    var configuredScreenMode: StreamMode {
        selectedStreamPreset.screenMode
    }

    var configuredMouseModePreference: StreamMouseModePreference {
        selectedStreamPreset.mouseMode
    }

    var configuredMouseMode: StreamMouseMode {
        streamMouseMode(for: selectedStreamPreset.mouseMode)
    }

    var currentStreamResolution: StreamConfiguration.Video.Resolution? {
        if let activeSessionController {
            return activeSessionController.configuration.video.resolution
        }

        guard currentRunningApplicationID != 0 else {
            return nil
        }

        return selectedStreamPreset.resolution
    }

    var currentStreamFPS: Int? {
        if let activeSessionController {
            return activeSessionController.configuration.video.fps
        }

        guard currentRunningApplicationID != 0 else {
            return nil
        }

        return selectedStreamPreset.fps
    }

    var configuredStreamResolution: StreamConfiguration.Video.Resolution {
        selectedStreamPreset.resolution
    }

    var configuredStreamFPS: Int {
        selectedStreamPreset.fps
    }

    var hasWakeOnLANConfiguration: Bool {
        pairedHost?.wakeOnLANConfiguration != nil
    }

    var canLaunchDesktop: Bool {
        guard pairedHost != nil, isHostReachable, !launchInProgress, !stopInProgress else {
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

    func performMenuBarPopupAction(_ action: MenuBarPopupAction) {
        switch action {
        case .none:
            return
        case .wakeUp:
            sendWakeOnLANMagicPacket()
        case .start:
            launchDesktop()
        case .resume:
            resumeRunningApplication()
        case .pause:
            pauseRunningApplication()
        case .stop:
            stopRunningApplication()
        }
    }

    func setSelectedStreamPreset(_ presetID: StreamPresetID) {
        guard !launchInProgress, !stopInProgress else {
            return
        }

        guard selectedStreamPresetID != presetID else {
            return
        }

        do {
            try saveSelectedStreamPresetID(presetID)
            reconnectActiveStreamIfNeeded()
        } catch {
            libraryActionError = error.localizedDescription
        }
    }

    func saveStreamPreset(
        _ presetID: StreamPresetID,
        screenMode: StreamMode,
        resolution: StreamConfiguration.Video.Resolution,
        fps: Int,
        mouseMode: StreamMouseModePreference
    ) throws {
        guard AppSettings.Video.isSupportedResolution(resolution) else {
            throw AppSettingsError.unsupportedResolution
        }

        guard AppSettings.Video.isSupportedFPS(fps) else {
            throw AppSettingsError.unsupportedFrameRate
        }

        var updatedSettings = settings
        if updatedSettings.video.supportedResolutions.contains(resolution) == false {
            updatedSettings.video.supportedResolutions = AppSettings.Video.normalizedSupportedResolutions(
                updatedSettings.video.supportedResolutions + [resolution]
            )
        }

        updatedSettings.video.setPreset(
            .init(
                screenMode: screenMode,
                resolution: resolution,
                fps: fps,
                mouseMode: mouseMode
            ),
            for: presetID
        )

        try persistSettings(updatedSettings)
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

    func saveSupportedResolutions(_ resolutions: [StreamConfiguration.Video.Resolution]) throws {
        var updatedSettings = settings
        let normalizedResolutions = AppSettings.Video.normalizedSupportedResolutions(resolutions)
        updatedSettings.video.supportedResolutions = normalizedResolutions

        if let fallbackResolution = normalizedResolutions.first {
            for presetID in StreamPresetID.allCases {
                let preset = updatedSettings.video.preset(presetID)
                if normalizedResolutions.contains(preset.resolution) == false {
                    updatedSettings.video.setPreset(
                        .init(
                            screenMode: preset.screenMode,
                            resolution: fallbackResolution,
                            fps: preset.fps,
                            mouseMode: preset.mouseMode
                        ),
                        for: presetID
                    )
                }
            }
        }

        try persistSettings(updatedSettings)
    }

    func saveInputSettings(
        rawMouseSensitivity: Double
    ) throws {
        var updatedSettings = settings
        updatedSettings.input = .init(rawMouseSensitivity: rawMouseSensitivity)

        try persistSettings(updatedSettings)

        if activeSessionController != nil {
            activeStreamWindowController?.updateInputConfiguration(
                .init(rawMouseSensitivity: updatedSettings.input.rawMouseSensitivity)
            )
        }
    }

    func resetPairing() async throws {
        libraryRefreshTask?.cancel()
        libraryRefreshTask = nil
        hostStateRefreshTask?.cancel()
        hostStateRefreshTask = nil
        wakeMonitoringTask?.cancel()
        wakeMonitoringTask = nil
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
        wakeInProgress = false
        libraryActionError = nil
        currentRunningApplicationID = 0
        hostReachabilityState = .unknown
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
        wakeInProgress = false
        libraryActionError = nil
        currentRunningApplicationID = 0
        hostReachabilityState = .unknown
    }

    func stopActiveSession() {
        Task { [weak self] in
            await self?.teardownActiveSession(closeErrorWindow: true)
        }
    }

    func sendWakeOnLANMagicPacket() {
        guard let configuration = pairedHost?.wakeOnLANConfiguration else {
            libraryActionError = "Wake-on-LAN is not configured for this host."
            return
        }

        libraryActionError = nil
        wakeInProgress = true
        wakeMonitoringTask?.cancel()

        let wakeOnLANClient = wakeOnLANClient
        wakeMonitoringTask = Task { [weak self] in
            do {
                try await Self.sendWakeOnLANMagicPacketRetries(
                    using: wakeOnLANClient,
                    configuration: configuration
                )

                for attempt in 0..<15 {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: attempt == 0 ? 1_500_000_000 : 1_000_000_000)

                    guard let self else {
                        return
                    }

                    if await self.refreshHostState() {
                        await MainActor.run {
                            self.wakeInProgress = false
                            self.refreshLibraryAfterWakeOnLAN()
                        }
                        return
                    }
                }

                await MainActor.run {
                    self?.wakeInProgress = false
                }
            } catch {
                if error is CancellationError {
                    await MainActor.run {
                        self?.wakeInProgress = false
                    }
                    return
                }

                await MainActor.run {
                    self?.wakeInProgress = false
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

                let selectedPreset = await MainActor.run { self.selectedStreamPreset }
                let requestResume = runningApplicationID == applicationID
                let configuration = try await MainActor.run {
                    try self.settings.makeConfiguration(
                        appID: applicationID,
                        autoConnectOnLaunch: false,
                        requestResume: requestResume,
                        resolution: selectedPreset.resolution,
                        fps: selectedPreset.fps
                    )
                }

                await MainActor.run {
                    self.startSession(
                        configuration: configuration,
                        launchesFullscreen: selectedPreset.screenMode == .fullscreen,
                        mouseMode: self.streamMouseMode(for: selectedPreset.mouseMode)
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
            hostReachabilityState = .reachable
            if stopInProgress, runningStatus.currentApplicationID == 0 {
                stopInProgress = false
                libraryActionError = nil
            }

            if wakeInProgress {
                wakeInProgress = false
            }

            currentRunningApplicationID = runningStatus.currentApplicationID
            libraryState = .loaded(applicationsMarkingRunning(applications, runningApplicationID: runningStatus.currentApplicationID))
        case let .failure(error):
            hostReachabilityState = .unreachable(error.localizedDescription)
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

    @discardableResult
    private func refreshHostState() async -> Bool {
        guard pairedHost != nil else {
            hostReachabilityState = .unknown
            return false
        }

        do {
            guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
                hostReachabilityState = .unknown
                return false
            }

            let runningStatus = try await libraryClient.fetchRunningStatus(using: artifacts)

            guard !Task.isCancelled else {
                return false
            }

            hostReachabilityState = .reachable
            applyRunningStatus(runningStatus)

            if shouldRefreshLibrary(for: runningStatus.currentApplicationID) {
                refreshLibrary(force: true, showLoadingIndicator: false)
            }
            return true
        } catch {
            guard !Task.isCancelled else {
                return false
            }

            hostReachabilityState = .unreachable(error.localizedDescription)
            return false
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

    private func saveSelectedStreamPresetID(_ presetID: StreamPresetID) throws {
        var updatedSettings = settings
        updatedSettings.selectedStreamPresetID = presetID
        try persistSettings(updatedSettings)
    }

    private func streamMouseMode(for preference: StreamMouseModePreference) -> StreamMouseMode {
        switch preference {
        case .absolute:
            return .absolute
        case .raw:
            return .raw
        }
    }

    private func reconnectActiveStreamIfNeeded() {
        guard let applicationID = activeStreamApplicationID else {
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

                let selectedPreset = await MainActor.run { self.selectedStreamPreset }

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
                        resolution: selectedPreset.resolution,
                        fps: selectedPreset.fps
                    )
                }

                await MainActor.run {
                    self.startSession(
                        configuration: configuration,
                        launchesFullscreen: selectedPreset.screenMode == .fullscreen,
                        mouseMode: self.streamMouseMode(for: selectedPreset.mouseMode)
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
        configuration: StreamConfiguration,
        launchesFullscreen: Bool,
        mouseMode: StreamMouseMode
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
            mouseMode: mouseMode
        )
        sessionController.onInputResetRequested = { [weak streamWindowController] in
            streamWindowController?.resetLocalInputState()
        }
        errorWindowController.onVisibilityChange = { [weak self] (isVisible: Bool) in
            guard let self else {
                return
            }

            if isVisible {
                self.setDockVisibility(true)
            } else if self.activeStreamWindowController?.isWindowVisible != true {
                self.setDockVisibility(false)
            }
        }
        streamWindowController.onVisibilityChange = { [weak self, weak streamWindowController] (isVisible: Bool) in
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

        guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
            stopInProgress = false
            throw AppSettingsError.missingHost
        }

        do {
            try await libraryClient.stopRunningApplication(using: artifacts)
        } catch {
            stopInProgress = false
            throw error
        }

        await MainActor.run {
            self.hostReachabilityState = .reachable
        }
    }

    private var menuBarPopupState: MenuBarPopupState {
        if activeSessionController != nil || launchInProgress {
            return .streaming
        }

        if currentRunningApplicationID != 0 {
            return .paused
        }

        if isHostReachable {
            return .ready
        }

        return .offline
    }

    private var isHostReachable: Bool {
        if case .reachable = hostReachabilityState {
            return true
        }

        return false
    }

    private var offlineDescriptionText: String {
        if pairedHost == nil {
            return "Open Settings to pair a Sunshine host."
        }

        if wakeInProgress {
            return "Waiting for the Sunshine host to wake up."
        }

        if case let .unreachable(message) = hostReachabilityState,
           !message.isEmpty {
            return message
        }

        return "Sunshine host is unavailable"
    }

    private var configuredStreamInfoText: String {
        let resolution = currentStreamResolution ?? configuredStreamResolution
        let fps = currentStreamFPS ?? configuredStreamFPS
        return "\(resolution.width) x \(resolution.height) @ \(fps) Hz"
    }

    private var offlinePrimaryButton: MenuBarPopupButton {
        if pairedHost == nil {
            return .init(
                title: "Start",
                systemImage: "play.fill",
                action: .none,
                isEnabled: false,
                showsProgress: false
            )
        }

        if wakeInProgress {
            return .init(
                title: "Waking Up",
                systemImage: nil,
                action: .none,
                isEnabled: false,
                showsProgress: true
            )
        }

        return .init(
            title: "Wake Up",
            systemImage: hasWakeOnLANConfiguration ? "wake.circle" : "play.fill",
            action: hasWakeOnLANConfiguration ? .wakeUp : .none,
            isEnabled: hasWakeOnLANConfiguration,
            showsProgress: false
        )
    }

    private var disabledStopButton: MenuBarPopupButton {
        .init(
            title: "Stop",
            systemImage: "stop.fill",
            action: .none,
            isEnabled: false,
            showsProgress: false
        )
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
