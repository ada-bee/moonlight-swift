import MoonlightCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var hostInput = ""
    @State private var macAddress = ""
    @State private var broadcastAddress = ""
    @State private var hostFeedbackMessage: String?
    @State private var hostFeedbackIsError = false
    @State private var wakeOnLANFeedbackMessage: String?
    @State private var wakeOnLANFeedbackIsError = false
    @State private var resolutionWidthInput = ""
    @State private var resolutionHeightInput = ""
    @State private var selectedResolutionID: String?
    @State private var videoFeedbackMessage: String?
    @State private var videoFeedbackIsError = false
    @State private var resetInProgress = false

    var body: some View {
        Form {
            Section("Streaming") {
                supportedResolutionsSection
            }

            Section("Sunshine Host") {
                sunshineHostSection
            }

            Section("Wake On LAN") {
                wakeOnLANSection
            }
        }
        .onAppear(perform: loadState)
        .onReceive(coordinator.$settings) { _ in
            hostInput = coordinator.settings.host?.displayString ?? ""
            clearHostFeedbackIfNeeded()
            syncSelectedResolutionIfNeeded()
        }
        .onReceive(coordinator.$pairedHost) { _ in
            loadWakeOnLANConfiguration()
            clearHostFeedbackIfNeeded()
        }
        .onReceive(coordinator.$pairingState) { state in
            guard case let .failed(message) = state else {
                return
            }

            hostFeedbackMessage = message
            hostFeedbackIsError = true
        }
    }

    private var sunshineHostSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair here instead of the main window. Enter the Sunshine host as ip:port, then pair or update the current host.")
                .foregroundStyle(.secondary)

            TextField("192.168.1.10:47989", text: $hostInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    startPairing()
                }

            pairedHostSummary

            HStack(spacing: 12) {
                Button(pairButtonTitle, action: startPairing)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedHostInput.isEmpty || coordinator.pairingState.isInProgress)

                Button("Reset", role: .destructive, action: resetPairing)
                    .buttonStyle(.bordered)
                    .disabled(!hasConfiguredHost || resetInProgress || coordinator.pairingState.isInProgress)
            }

            if let statusText = pairingStatusText {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }

            if let pin = pairingPIN {
                Text(pin)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .padding(.top, 2)
            }

            if let hostFeedbackMessage {
                Text(hostFeedbackMessage)
                    .foregroundStyle(hostFeedbackIsError ? Color(nsColor: .systemRed) : .secondary)
            }
        }
    }

    private var wakeOnLANSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add or change the host MAC address used for Wake-on-LAN packets. Sunshine pairing does not expose it here, so enter it manually.")
                .foregroundStyle(.secondary)

            TextField("00:11:22:33:44:55", text: $macAddress)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(!hasPairedHost)

            TextField("255.255.255.255 (optional)", text: $broadcastAddress)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(!hasPairedHost)

            HStack(spacing: 12) {
                Button("Save WOL") {
                    saveWakeOnLANConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasPairedHost || trimmedMACAddress.isEmpty)

                Button("Clear WOL") {
                    clearWakeOnLANConfiguration()
                }
                .buttonStyle(.bordered)
                .disabled(!hasPairedHost || coordinator.pairedHost?.wakeOnLANConfiguration == nil)
            }

            if let wakeOnLANFeedbackMessage {
                Text(wakeOnLANFeedbackMessage)
                    .foregroundStyle(wakeOnLANFeedbackIsError ? Color(nsColor: .systemRed) : .secondary)
            }

            if !hasPairedHost {
                Text("Pair with a host before saving Wake-on-LAN settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var supportedResolutionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the windowed resolutions that appear in the library. Fullscreen always uses the display's native resolution and refresh rate.")
                .foregroundStyle(.secondary)

            List(selection: $selectedResolutionID) {
                ForEach(supportedResolutions, id: \.self) { resolution in
                    Text(resolutionLabel(resolution))
                        .tag(resolutionID(for: resolution))
                }
            }
            .frame(minHeight: 170)

            HStack(alignment: .top, spacing: 12) {
                TextField("Width", text: $resolutionWidthInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)

                TextField("Height", text: $resolutionHeightInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)

                Button("Add") {
                    addSupportedResolution()
                }
                .buttonStyle(.borderedProminent)
                .disabled(candidateResolution == nil)

                Button("Remove") {
                    removeSelectedResolution()
                }
                .buttonStyle(.bordered)
                .disabled(selectedSupportedResolution == nil)

                Button("Reset to Defaults") {
                    resetSupportedResolutions()
                }
                .buttonStyle(.bordered)
            }

            Text("Custom resolutions must use positive even numbers for width and height.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let videoFeedbackMessage {
                Text(videoFeedbackMessage)
                    .foregroundStyle(videoFeedbackIsError ? Color(nsColor: .systemRed) : .secondary)
            }
        }
    }

    @ViewBuilder
    private var pairedHostSummary: some View {
        if let pairedHost = coordinator.pairedHost {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current paired host")
                    .foregroundStyle(.secondary)

                Text(pairedHost.host.displayString)
                    .font(.system(.body, design: .monospaced))

                if let macAddress = pairedHost.wakeOnLANConfiguration?.macAddress {
                    Text("Wake-on-LAN MAC: \(macAddress)")
                        .foregroundStyle(.secondary)
                }
            }
        } else if hasConfiguredHost {
            Text("No active pairing is stored for the configured host yet.")
                .foregroundStyle(.secondary)
        } else {
            Text("No Sunshine host is configured yet.")
                .foregroundStyle(.secondary)
        }
    }

    private var hasConfiguredHost: Bool {
        coordinator.settings.host != nil
    }

    private var hasPairedHost: Bool {
        coordinator.pairedHost != nil
    }

    private var trimmedHostInput: String {
        hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMACAddress: String {
        macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supportedResolutions: [MVPConfiguration.Video.Resolution] {
        coordinator.settings.video.supportedResolutions
    }

    private var candidateResolution: MVPConfiguration.Video.Resolution? {
        guard let width = Int(trimmedResolutionWidthInput),
              let height = Int(trimmedResolutionHeightInput)
        else {
            return nil
        }

        let resolution = MVPConfiguration.Video.Resolution(width: width, height: height)
        guard AppSettings.Video.isSupportedResolution(resolution) else {
            return nil
        }

        return resolution
    }

    private var selectedSupportedResolution: MVPConfiguration.Video.Resolution? {
        guard let selectedResolutionID else {
            return nil
        }

        return supportedResolutions.first(where: { resolutionID(for: $0) == selectedResolutionID })
    }

    private var trimmedResolutionWidthInput: String {
        resolutionWidthInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedResolutionHeightInput: String {
        resolutionHeightInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pairButtonTitle: String {
        coordinator.pairingState.isInProgress ? "Pairing..." : (hasPairedHost ? "Change Host" : "Start Pairing")
    }

    private var pairingStatusText: String? {
        if case let .inProgress(status, _) = coordinator.pairingState {
            return status
        }

        return nil
    }

    private var pairingPIN: String? {
        if case let .inProgress(_, pin) = coordinator.pairingState {
            return pin
        }

        return nil
    }

    private func loadState() {
        hostInput = coordinator.settings.host?.displayString ?? ""
        loadWakeOnLANConfiguration()
        clearHostFeedbackIfNeeded()
        syncSelectedResolutionIfNeeded()
    }

    private func clearHostFeedbackIfNeeded() {
        if coordinator.pairingState.isInProgress {
            hostFeedbackMessage = nil
            hostFeedbackIsError = false
            return
        }

        if case .idle = coordinator.pairingState, coordinator.pairedHost?.host.displayString == trimmedHostInput {
            hostFeedbackMessage = hasPairedHost ? "Sunshine host is paired and ready." : nil
            hostFeedbackIsError = false
        }
    }

    private func loadWakeOnLANConfiguration() {
        if let configuration = coordinator.pairedHost?.wakeOnLANConfiguration {
            macAddress = configuration.macAddress
            broadcastAddress = configuration.broadcastAddress ?? ""
        } else {
            macAddress = ""
            broadcastAddress = ""
        }

        wakeOnLANFeedbackMessage = nil
        wakeOnLANFeedbackIsError = false
    }

    private func syncSelectedResolutionIfNeeded() {
        if let selectedResolutionID,
           supportedResolutions.contains(where: { resolutionID(for: $0) == selectedResolutionID })
        {
            return
        }

        selectedResolutionID = supportedResolutions.first.map(resolutionID(for:))
    }

    private func startPairing() {
        hostFeedbackMessage = nil
        hostFeedbackIsError = false
        coordinator.startPairing(hostInput: hostInput)
    }

    private func resetPairing() {
        hostFeedbackMessage = nil
        hostFeedbackIsError = false
        resetInProgress = true

        Task {
            do {
                try await coordinator.resetPairing()
                await MainActor.run {
                    hostInput = ""
                    loadWakeOnLANConfiguration()
                    hostFeedbackMessage = "Sunshine host configuration cleared."
                    hostFeedbackIsError = false
                    resetInProgress = false
                }
            } catch {
                await MainActor.run {
                    hostFeedbackMessage = error.localizedDescription
                    hostFeedbackIsError = true
                    resetInProgress = false
                }
            }
        }
    }

    private func saveWakeOnLANConfiguration() {
        do {
            try coordinator.saveWakeOnLANConfiguration(macAddress: macAddress, broadcastAddress: broadcastAddress)
            loadWakeOnLANConfiguration()
            wakeOnLANFeedbackMessage = "Wake-on-LAN will be sent when GameStream launches."
            wakeOnLANFeedbackIsError = false
        } catch {
            wakeOnLANFeedbackMessage = error.localizedDescription
            wakeOnLANFeedbackIsError = true
        }
    }

    private func clearWakeOnLANConfiguration() {
        do {
            try coordinator.clearWakeOnLANConfiguration()
            loadWakeOnLANConfiguration()
            wakeOnLANFeedbackMessage = "Wake-on-LAN settings cleared."
            wakeOnLANFeedbackIsError = false
        } catch {
            wakeOnLANFeedbackMessage = error.localizedDescription
            wakeOnLANFeedbackIsError = true
        }
    }

    private func addSupportedResolution() {
        guard let resolution = candidateResolution else {
            videoFeedbackMessage = "Enter a valid resolution using positive even numbers."
            videoFeedbackIsError = true
            return
        }

        var updatedResolutions = supportedResolutions
        if updatedResolutions.contains(resolution) == false {
            updatedResolutions.append(resolution)
        }

        saveSupportedResolutions(updatedResolutions, successMessage: "Windowed resolutions updated.")
        selectedResolutionID = resolutionID(for: resolution)
        resolutionWidthInput = ""
        resolutionHeightInput = ""
    }

    private func removeSelectedResolution() {
        guard let selectedSupportedResolution else {
            return
        }

        let updatedResolutions = supportedResolutions.filter { $0 != selectedSupportedResolution }
        saveSupportedResolutions(updatedResolutions, successMessage: "Windowed resolutions updated.")
        syncSelectedResolutionIfNeeded()
    }

    private func resetSupportedResolutions() {
        saveSupportedResolutions(
            AppSettings.Video.defaultSupportedResolutions,
            successMessage: "Default windowed resolutions restored."
        )
        syncSelectedResolutionIfNeeded()
    }

    private func saveSupportedResolutions(
        _ resolutions: [MVPConfiguration.Video.Resolution],
        successMessage: String
    ) {
        do {
            try coordinator.saveSupportedResolutions(resolutions)
            videoFeedbackMessage = successMessage
            videoFeedbackIsError = false
        } catch {
            videoFeedbackMessage = error.localizedDescription
            videoFeedbackIsError = true
        }
    }

    private func resolutionLabel(_ resolution: MVPConfiguration.Video.Resolution) -> String {
        "\(resolution.width) x \(resolution.height)"
    }

    private func resolutionID(for resolution: MVPConfiguration.Video.Resolution) -> String {
        "\(resolution.width)x\(resolution.height)"
    }
}

private extension AppCoordinator.PairingState {
    var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }

        return false
    }
}
