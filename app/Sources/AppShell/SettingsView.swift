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
    @State private var inputFeedbackMessage: String?
    @State private var inputFeedbackIsError = false
    @State private var selectedResolutionID = ""
    @State private var selectedFPS = 60
    @State private var resolutionWidthInput = ""
    @State private var resolutionHeightInput = ""
    @State private var rawMouseSensitivity = AppSettings.Input.defaultRawMouseSensitivity
    @State private var streamFeedbackMessage: String?
    @State private var streamFeedbackIsError = false
    @State private var resetInProgress = false

    private static let standardFPSOptions = [30, 60, 90, 120]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                preferenceSection(
                    title: "Stream",
                    description: "Set the single windowed stream resolution and frame rate, and manage the available resolution list."
                ) {
                    settingsGroup {
                        labeledRow("Resolution") {
                            Picker("Resolution", selection: selectedResolutionBinding) {
                                ForEach(supportedResolutions, id: \.self) { resolution in
                                    Text(resolutionLabel(resolution))
                                        .tag(resolutionID(for: resolution))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220, alignment: .leading)
                            .pickerStyle(.menu)
                        }

                        Divider()

                        labeledRow("Frame Rate") {
                            Picker("Frame Rate", selection: selectedFPSBinding) {
                                ForEach(fpsOptions, id: \.self) { fps in
                                    Text("\(fps) Hz")
                                        .tag(fps)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 140, alignment: .leading)
                            .pickerStyle(.menu)
                        }
                    }

                    settingsGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Custom Resolutions")
                                .font(.headline)

                            Text("Add any supported window size to the list shown in the Resolution menu.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                TextField("Width", text: $resolutionWidthInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)

                                Text("x")
                                    .foregroundStyle(.secondary)

                                TextField("Height", text: $resolutionHeightInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)

                                Button("Add", action: addSupportedResolution)
                                    .buttonStyle(.bordered)
                                    .disabled(candidateResolution == nil)

                                Button("Remove", role: .destructive, action: removeSelectedResolution)
                                    .buttonStyle(.bordered)
                                    .disabled(selectedSupportedResolution == nil || supportedResolutions.count <= 1)

                                Spacer(minLength: 0)

                                Button("Restore Defaults", action: resetSupportedResolutions)
                                    .buttonStyle(.bordered)
                            }

                            Text("Widths and heights must be positive even numbers.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    feedbackText(streamFeedbackMessage, isError: streamFeedbackIsError)
                }

                preferenceSection(
                    title: "Input",
                    description: "Tune relative mouse input for Windows Sunshine hosts. The slider trims GameController mouse deltas before they are sent to Sunshine."
                ) {
                    settingsGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            labeledRow("Raw Mouse Scale") {
                                HStack(spacing: 12) {
                                    Slider(
                                        value: rawMouseSensitivityBinding,
                                        in: 0.5...1.5,
                                        step: 0.01
                                    )
                                    .frame(maxWidth: 220)

                                    Text(rawMouseSensitivityLabel)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 52, alignment: .trailing)
                                }
                            }

                            Text("Lower this if remote desktop motion feels too fast. The existing fractional carry stays intact, so this only changes overall scale.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    feedbackText(inputFeedbackMessage, isError: inputFeedbackIsError)
                }

                preferenceSection(
                    title: "Sunshine",
                    description: "Review the current host, update Wake-on-LAN details, or pair a different machine."
                ) {
                    settingsGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            hostSummaryView

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Wake-on-LAN MAC Address")
                                    .font(.subheadline.weight(.medium))

                                TextField("00:11:22:33:44:55", text: $macAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .disabled(!hasPairedHost)

                                TextField("Broadcast Address (Optional)", text: $broadcastAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .disabled(!hasPairedHost)

                                HStack(spacing: 10) {
                                    Button("Save", action: saveWakeOnLANConfiguration)
                                        .buttonStyle(.bordered)
                                        .disabled(!hasPairedHost || trimmedMACAddress.isEmpty)

                                    Button("Clear", role: .destructive, action: clearWakeOnLANConfiguration)
                                        .buttonStyle(.bordered)
                                        .disabled(!hasPairedHost || coordinator.pairedHost?.wakeOnLANConfiguration == nil)
                                }

                                if !hasPairedHost {
                                    Text("Pair a host before editing Wake-on-LAN settings.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let wakeOnLANFeedbackMessage {
                        feedbackText(wakeOnLANFeedbackMessage, isError: wakeOnLANFeedbackIsError)
                    }

                    settingsGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Pair New Host")
                                    .font(.headline)

                                Text("Enter the Sunshine host as an IP address and port.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            TextField("192.168.1.10:47989", text: $hostInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .onSubmit(startPairing)

                            HStack(spacing: 10) {
                                Button(pairButtonTitle, action: startPairing)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(trimmedHostInput.isEmpty || coordinator.pairingState.isInProgress)

                                Button("Forget Host", role: .destructive, action: resetPairing)
                                    .buttonStyle(.bordered)
                                    .disabled(!hasConfiguredHost || resetInProgress || coordinator.pairingState.isInProgress)
                            }

                            if let statusText = pairingStatusText {
                                Text(statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let pin = pairingPIN {
                                Text(pin)
                                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    feedbackText(hostFeedbackMessage, isError: hostFeedbackIsError)
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadState)
        .onReceive(coordinator.$settings) { _ in
            hostInput = coordinator.settings.host?.displayString ?? ""
            clearHostFeedbackIfNeeded()
            syncSelectedResolutionIfNeeded()
            syncSelectedFPSIfNeeded()
            syncInputSettings()
            updateInputFeedback()
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

    private var hostSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Host")
                .font(.headline)

            if let pairedHost = coordinator.pairedHost {
                LabeledContent("Address", value: pairedHost.host.displayString)
                    .font(.system(.body, design: .monospaced))

                if let macAddress = pairedHost.wakeOnLANConfiguration?.macAddress {
                    LabeledContent("MAC", value: macAddress)
                        .font(.system(.body, design: .monospaced))
                }

                if let broadcastAddress = pairedHost.wakeOnLANConfiguration?.broadcastAddress,
                   broadcastAddress.isEmpty == false
                {
                    LabeledContent("Broadcast", value: broadcastAddress)
                        .font(.system(.body, design: .monospaced))
                }
            } else if let configuredHost = coordinator.settings.host?.displayString {
                LabeledContent("Address", value: configuredHost)
                    .font(.system(.body, design: .monospaced))

                Text("The host is saved, but pairing has not completed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Sunshine host is configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    private var supportedResolutions: [StreamConfiguration.Video.Resolution] {
        coordinator.settings.video.supportedResolutions
    }

    private var defaultResolution: StreamConfiguration.Video.Resolution {
        coordinator.windowedStreamResolution
    }

    private var candidateResolution: StreamConfiguration.Video.Resolution? {
        guard let width = Int(trimmedResolutionWidthInput),
              let height = Int(trimmedResolutionHeightInput)
        else {
            return nil
        }

        let resolution = StreamConfiguration.Video.Resolution(width: width, height: height)
        guard AppSettings.Video.isSupportedResolution(resolution) else {
            return nil
        }

        return resolution
    }

    private var selectedSupportedResolution: StreamConfiguration.Video.Resolution? {
        supportedResolutions.first(where: { resolutionID(for: $0) == selectedResolutionID })
    }

    private var trimmedResolutionWidthInput: String {
        resolutionWidthInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedResolutionHeightInput: String {
        resolutionHeightInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pairButtonTitle: String {
        coordinator.pairingState.isInProgress ? "Pairing..." : (hasPairedHost ? "Pair New Host" : "Pair Host")
    }

    private var selectedResolutionBinding: Binding<String> {
        Binding(
            get: { selectedResolutionID },
            set: { newValue in
                selectedResolutionID = newValue
                saveWindowedVideoSettingsIfPossible()
            }
        )
    }

    private var selectedFPSBinding: Binding<Int> {
        Binding(
            get: { selectedFPS },
            set: { newValue in
                selectedFPS = newValue
                saveWindowedVideoSettingsIfPossible()
            }
        )
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

    private var fpsOptions: [Int] {
        var options = Set(Self.standardFPSOptions)
        options.insert(coordinator.windowedStreamFPS)
        return options.sorted()
    }

    private var rawMouseSensitivityLabel: String {
        rawMouseSensitivity.formatted(.number.precision(.fractionLength(2)))
    }

    private var rawMouseSensitivityBinding: Binding<Double> {
        Binding(
            get: { rawMouseSensitivity },
            set: { newValue in
                rawMouseSensitivity = newValue
                saveInputSettingsIfPossible()
            }
        )
    }

    private func loadState() {
        hostInput = coordinator.settings.host?.displayString ?? ""
        loadWakeOnLANConfiguration()
        clearHostFeedbackIfNeeded()
        syncSelectedResolutionIfNeeded()
        syncSelectedFPSIfNeeded()
        syncInputSettings()
        updateInputFeedback()
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
        let defaultResolutionID = resolutionID(for: defaultResolution)
        if supportedResolutions.contains(defaultResolution) {
            selectedResolutionID = defaultResolutionID
        } else {
            selectedResolutionID = supportedResolutions.first.map(resolutionID(for:)) ?? ""
        }
    }

    private func syncSelectedFPSIfNeeded() {
        selectedFPS = coordinator.windowedStreamFPS
    }

    private func syncInputSettings() {
        rawMouseSensitivity = coordinator.settings.input.rawMouseSensitivity
    }

    private func updateInputFeedback(message: String? = nil, isError: Bool = false) {
        if let message {
            inputFeedbackMessage = message
            inputFeedbackIsError = isError
            return
        }

        let effectiveScale = coordinator.settings.input.effectiveRawMouseScale
        inputFeedbackMessage = "Effective relative scale: \(effectiveScale.formatted(.number.precision(.fractionLength(2))))x"
        inputFeedbackIsError = false
    }

    private func saveWindowedVideoSettingsIfPossible() {
        guard let resolution = supportedResolutions.first(where: { resolutionID(for: $0) == selectedResolutionID }) else {
            return
        }

        do {
            try coordinator.saveWindowedVideoSettings(resolution: resolution, fps: selectedFPS)
            streamFeedbackMessage = "Windowed stream settings updated."
            streamFeedbackIsError = false
            syncSelectedResolutionIfNeeded()
            syncSelectedFPSIfNeeded()
        } catch {
            streamFeedbackMessage = error.localizedDescription
            streamFeedbackIsError = true
        }
    }

    private func saveInputSettingsIfPossible() {
        do {
            try coordinator.saveInputSettings(rawMouseSensitivity: rawMouseSensitivity)
            syncInputSettings()
            updateInputFeedback()
        } catch {
            updateInputFeedback(message: error.localizedDescription, isError: true)
        }
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
            streamFeedbackMessage = "Enter a valid resolution using positive even numbers."
            streamFeedbackIsError = true
            return
        }

        var updatedResolutions = supportedResolutions
        if updatedResolutions.contains(resolution) == false {
            updatedResolutions.append(resolution)
        }

        saveSupportedResolutions(updatedResolutions, successMessage: "Resolution list updated.")
        selectedResolutionID = resolutionID(for: resolution)
        resolutionWidthInput = ""
        resolutionHeightInput = ""
        saveWindowedVideoSettingsIfPossible()
    }

    private func removeSelectedResolution() {
        guard let selectedSupportedResolution else {
            return
        }

        let updatedResolutions = supportedResolutions.filter { $0 != selectedSupportedResolution }
        saveSupportedResolutions(updatedResolutions, successMessage: "Resolution list updated.")
        syncSelectedResolutionIfNeeded()
        saveWindowedVideoSettingsIfPossible()
    }

    private func resetSupportedResolutions() {
        saveSupportedResolutions(
            AppSettings.Video.defaultSupportedResolutions,
            successMessage: "Default resolutions restored."
        )
        syncSelectedResolutionIfNeeded()
        saveWindowedVideoSettingsIfPossible()
    }

    private func saveSupportedResolutions(
        _ resolutions: [StreamConfiguration.Video.Resolution],
        successMessage: String
    ) {
        do {
            try coordinator.saveSupportedResolutions(resolutions)
            streamFeedbackMessage = successMessage
            streamFeedbackIsError = false
        } catch {
            streamFeedbackMessage = error.localizedDescription
            streamFeedbackIsError = true
        }
    }

    private func preferenceSection<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func labeledRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .frame(width: 110, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func feedbackText(_ message: String?, isError: Bool) -> some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(isError ? Color(nsColor: .systemRed) : .secondary)
        }
    }

    private func resolutionLabel(_ resolution: StreamConfiguration.Video.Resolution) -> String {
        "\(resolution.width) x \(resolution.height)"
    }

    private func resolutionID(for resolution: StreamConfiguration.Video.Resolution) -> String {
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
