import MoonlightCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var hostInput = ""
    @State private var macAddress = ""
    @State private var broadcastAddress = ""
    @State private var showPairingFlow = false

    @State private var hostFeedbackMessage: String?
    @State private var hostFeedbackIsError = false
    @State private var wakeOnLANFeedbackMessage: String?
    @State private var wakeOnLANFeedbackIsError = false
    @State private var inputFeedbackMessage: String?
    @State private var inputFeedbackIsError = false
    @State private var streamFeedbackMessage: String?
    @State private var streamFeedbackIsError = false
    @State private var resetInProgress = false

    @State private var rawMouseSensitivity = AppSettings.Input.defaultRawMouseSensitivity

    @State private var windowedWidthInput = ""
    @State private var windowedHeightInput = ""
    @State private var windowedFPSInput = ""

    @State private var fullscreenWidthInput = ""
    @State private var fullscreenHeightInput = ""
    @State private var fullscreenFPSInput = ""
    @State private var alwaysUseNativeFullscreenVideoMode = true
    @State private var alwaysUseNativeFullscreenRawMouseInput = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                streamSection
                inputSection
                sunshineSection
            }
            .padding(24)
        }
        .background(settingsBackground)
        .onAppear(perform: loadState)
        .onReceive(coordinator.$settings) { _ in
            syncVideoInputs()
            syncInputSettings()

            if showPairingFlow == false {
                hostInput = coordinator.settings.host?.displayString ?? ""
            }
        }
        .onReceive(coordinator.$pairedHost) { pairedHost in
            loadWakeOnLANConfiguration()

            if pairedHost != nil {
                showPairingFlow = false
                hostFeedbackMessage = "Sunshine host is paired and ready."
                hostFeedbackIsError = false
            }
        }
        .onReceive(coordinator.$pairingState) { state in
            if case let .failed(message) = state {
                hostFeedbackMessage = message
                hostFeedbackIsError = true
                resetInProgress = false
            } else if case .idle = state {
                resetInProgress = false
            }
        }
    }

    private var streamSection: some View {
        preferenceSection(
            title: "Video",
            description: "Configure the fixed launch values for windowed and fullscreen streaming."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                videoModeEditor(
                    title: "Windowed",
                    width: $windowedWidthInput,
                    height: $windowedHeightInput,
                    fps: $windowedFPSInput,
                    isDisabled: false,
                    action: saveWindowedVideoSettings
                )

                Divider()

                videoModeEditor(
                    title: "Fullscreen",
                    width: $fullscreenWidthInput,
                    height: $fullscreenHeightInput,
                    fps: $fullscreenFPSInput,
                    isDisabled: alwaysUseNativeFullscreenVideoMode,
                    action: saveFullscreenVideoSettings
                )

                Toggle("Always use display native resolution and framerate", isOn: nativeFullscreenVideoBinding)
                    .toggleStyle(.switch)

                Toggle("Always use native raw mouse input in fullscreen", isOn: nativeRawMouseBinding)
                    .toggleStyle(.switch)
            }

            feedbackText(streamFeedbackMessage, isError: streamFeedbackIsError)
        }
    }

    private var inputSection: some View {
        preferenceSection(
            title: "Input",
            description: "Tune relative mouse input."
        ) {
            labeledRow("Mouse Scale") {
                HStack(spacing: 12) {
                    Slider(
                        value: rawMouseSensitivityBinding,
                        in: 0.5...1.5,
                        step: 0.05,
                        minimumValueLabel: Text("0.5x"),
                        maximumValueLabel: Text("1.5x")
                    ) {
                        EmptyView()
                    }
                    .frame(width: 280)
                    .controlSize(.small)

                    Text(rawMouseSensitivityLabel)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
            }

            feedbackText(inputFeedbackMessage, isError: inputFeedbackIsError)
        }
    }

    private var sunshineSection: some View {
        preferenceSection(
            title: "Sunshine",
            description: "Manage the current host and pair a replacement when needed."
        ) {
            if showPairingFlow {
                pairingFlowCard
            } else {
                currentHostCard
            }

            feedbackText(hostFeedbackMessage, isError: hostFeedbackIsError)
            feedbackText(wakeOnLANFeedbackMessage, isError: wakeOnLANFeedbackIsError)
        }
    }

    private var currentHostCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Current Host")
                        .font(.headline)

                    Spacer(minLength: 12)

                    Button("Pair New Host", action: prepareForNewHostPairing)
                        .buttonStyle(.borderedProminent)
                        .disabled(resetInProgress || coordinator.pairingState.isInProgress)
                }

                if let currentHostDisplayString {
                    LabeledContent("Address", value: currentHostDisplayString)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("No Sunshine host is configured.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Wake-on-LAN")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 12) {
                        settingField(title: "MAC Address", placeholder: "00:11:22:33:44:55", text: $macAddress)
                        settingField(title: "Broadcast", placeholder: "192.168.1.255", text: $broadcastAddress)
                    }

                    HStack(spacing: 10) {
                        Button("Save", action: saveWakeOnLANConfiguration)
                            .buttonStyle(.bordered)
                            .disabled(!canSaveWakeOnLAN)

                        Button("Clear", role: .destructive, action: clearWakeOnLANConfiguration)
                            .buttonStyle(.bordered)
                            .disabled(coordinator.pairedHost?.wakeOnLANConfiguration == nil)
                    }
                }
                .disabled(currentHostDisplayString == nil)
            }
        }
    }

    private var pairingFlowCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pair New Host")
                        .font(.headline)

                    Spacer(minLength: 12)

                    if coordinator.pairingState.isInProgress == false {
                        Button("Cancel") {
                            hostFeedbackMessage = nil
                            hostFeedbackIsError = false
                            showPairingFlow = false
                        }
                        .buttonStyle(.bordered)
                    }
                }

                settingField(title: "Sunshine Host", placeholder: "192.168.1.10:47989", text: $hostInput)
                    .onSubmit(startPairing)

                HStack(spacing: 10) {
                    Button(pairButtonTitle, action: startPairing)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedHostInput.isEmpty || coordinator.pairingState.isInProgress || resetInProgress)
                }

                if let statusText = pairingStatusText {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }

                if let pin = pairingPIN {
                    Text(pin)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var nativeFullscreenVideoBinding: Binding<Bool> {
        Binding(
            get: { alwaysUseNativeFullscreenVideoMode },
            set: { newValue in
                alwaysUseNativeFullscreenVideoMode = newValue
                saveFullscreenPreferences()
            }
        )
    }

    private var nativeRawMouseBinding: Binding<Bool> {
        Binding(
            get: { alwaysUseNativeFullscreenRawMouseInput },
            set: { newValue in
                alwaysUseNativeFullscreenRawMouseInput = newValue
                saveFullscreenPreferences()
            }
        )
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

    private var rawMouseSensitivityLabel: String {
        rawMouseSensitivity.formatted(.number.precision(.fractionLength(2)))
    }

    private var currentHostDisplayString: String? {
        coordinator.pairedHost?.host.displayString ?? coordinator.settings.host?.displayString
    }

    private var trimmedHostInput: String {
        hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMACAddress: String {
        macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pairButtonTitle: String {
        coordinator.pairingState.isInProgress ? "Pairing..." : "Start Pairing"
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

    private var canSaveWakeOnLAN: Bool {
        coordinator.pairedHost != nil && trimmedMACAddress.isEmpty == false
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func loadState() {
        hostInput = coordinator.settings.host?.displayString ?? ""
        syncVideoInputs()
        syncInputSettings()
        loadWakeOnLANConfiguration()
    }

    private func syncVideoInputs() {
        windowedWidthInput = String(coordinator.windowedStreamResolution.width)
        windowedHeightInput = String(coordinator.windowedStreamResolution.height)
        windowedFPSInput = String(coordinator.windowedStreamFPS)

        fullscreenWidthInput = String(coordinator.fullscreenStreamResolution.width)
        fullscreenHeightInput = String(coordinator.fullscreenStreamResolution.height)
        fullscreenFPSInput = String(coordinator.fullscreenStreamFPS)

        alwaysUseNativeFullscreenVideoMode = coordinator.prefersNativeFullscreenVideoMode
        alwaysUseNativeFullscreenRawMouseInput = coordinator.prefersNativeFullscreenRawMouseInput
    }

    private func syncInputSettings() {
        rawMouseSensitivity = coordinator.settings.input.rawMouseSensitivity
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

    private func saveWindowedVideoSettings() {
        do {
            let resolution = try resolutionFromInputs(width: windowedWidthInput, height: windowedHeightInput)
            let fps = try fpsFromInput(windowedFPSInput)
            try coordinator.saveWindowedVideoSettings(resolution: resolution, fps: fps)
            streamFeedbackMessage = "Windowed settings updated."
            streamFeedbackIsError = false
            syncVideoInputs()
        } catch {
            streamFeedbackMessage = error.localizedDescription
            streamFeedbackIsError = true
        }
    }

    private func saveFullscreenVideoSettings() {
        do {
            let resolution = try resolutionFromInputs(width: fullscreenWidthInput, height: fullscreenHeightInput)
            let fps = try fpsFromInput(fullscreenFPSInput)
            try coordinator.saveFullscreenVideoSettings(resolution: resolution, fps: fps)
            streamFeedbackMessage = "Fullscreen settings updated."
            streamFeedbackIsError = false
            syncVideoInputs()
        } catch {
            streamFeedbackMessage = error.localizedDescription
            streamFeedbackIsError = true
        }
    }

    private func saveFullscreenPreferences() {
        do {
            try coordinator.saveFullscreenPresentationPreferences(
                prefersNativeVideoMode: alwaysUseNativeFullscreenVideoMode,
                prefersNativeRawMouseInput: alwaysUseNativeFullscreenRawMouseInput
            )
            streamFeedbackMessage = "Fullscreen preferences updated."
            streamFeedbackIsError = false
        } catch {
            streamFeedbackMessage = error.localizedDescription
            streamFeedbackIsError = true
        }
    }

    private func saveInputSettingsIfPossible() {
        do {
            try coordinator.saveInputSettings(rawMouseSensitivity: rawMouseSensitivity)
            inputFeedbackMessage = nil
            inputFeedbackIsError = false
            syncInputSettings()
        } catch {
            inputFeedbackMessage = error.localizedDescription
            inputFeedbackIsError = true
        }
    }

    private func prepareForNewHostPairing() {
        hostFeedbackMessage = nil
        hostFeedbackIsError = false
        showPairingFlow = true
        hostInput = ""

        guard currentHostDisplayString != nil else {
            loadWakeOnLANConfiguration()
            return
        }

        resetInProgress = true

        Task {
            do {
                try await coordinator.resetPairing()
                await MainActor.run {
                    loadWakeOnLANConfiguration()
                    hostFeedbackMessage = nil
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

    private func startPairing() {
        hostFeedbackMessage = nil
        hostFeedbackIsError = false
        coordinator.startPairing(hostInput: hostInput)
    }

    private func saveWakeOnLANConfiguration() {
        do {
            try coordinator.saveWakeOnLANConfiguration(macAddress: macAddress, broadcastAddress: broadcastAddress)
            loadWakeOnLANConfiguration()
            wakeOnLANFeedbackMessage = "Wake-on-LAN settings updated."
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

    private func resolutionFromInputs(
        width: String,
        height: String
    ) throws -> StreamConfiguration.Video.Resolution {
        guard let width = Int(width.trimmingCharacters(in: .whitespacesAndNewlines)),
              let height = Int(height.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw AppSettingsError.unsupportedResolution
        }

        let resolution = StreamConfiguration.Video.Resolution(width: width, height: height)
        guard AppSettings.Video.isSupportedResolution(resolution) else {
            throw AppSettingsError.unsupportedResolution
        }

        return resolution
    }

    private func fpsFromInput(_ value: String) throws -> Int {
        guard let fps = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              AppSettings.Video.isSupportedFPS(fps)
        else {
            throw AppSettingsError.unsupportedFrameRate
        }

        return fps
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
                .foregroundStyle(.secondary)

            settingsCard(content: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
            }
    }

    private func labeledRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(width: 110, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
    }

    private func videoModeEditor(
        title: String,
        width: Binding<String>,
        height: Binding<String>,
        fps: Binding<String>,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                settingField(title: "Width", placeholder: "1920", text: width)
                settingField(title: "Height", placeholder: "1080", text: height)
                settingField(title: "FPS", placeholder: "60", text: fps)

                VStack {
                    Spacer(minLength: 0)

                    Button("Apply", action: action)
                        .buttonStyle(.bordered)
                        .disabled(isDisabled)
                }
            }
            .disabled(isDisabled)
        }
    }

    private func settingField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
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
}

private extension AppCoordinator.PairingState {
    var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }

        return false
    }
}
