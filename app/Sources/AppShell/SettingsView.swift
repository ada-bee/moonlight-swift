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

    @State private var presetOneWidthInput = ""
    @State private var presetOneHeightInput = ""
    @State private var presetOneFPSInput = ""
    @State private var presetOneScreenMode: StreamMode = .windowed
    @State private var presetOneMouseMode: StreamMouseModePreference = .absolute

    @State private var presetTwoWidthInput = ""
    @State private var presetTwoHeightInput = ""
    @State private var presetTwoFPSInput = ""
    @State private var presetTwoScreenMode: StreamMode = .fullscreen
    @State private var presetTwoMouseMode: StreamMouseModePreference = .raw

    @State private var presetThreeWidthInput = ""
    @State private var presetThreeHeightInput = ""
    @State private var presetThreeFPSInput = ""
    @State private var presetThreeScreenMode: StreamMode = .fullscreen
    @State private var presetThreeMouseMode: StreamMouseModePreference = .raw

    @State private var presetFourWidthInput = ""
    @State private var presetFourHeightInput = ""
    @State private var presetFourFPSInput = ""
    @State private var presetFourScreenMode: StreamMode = .fullscreen
    @State private var presetFourMouseMode: StreamMouseModePreference = .raw

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
            syncPresetInputs()
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
            title: "Presets",
            description: "Configure the four launch presets shown in the menu bar popup."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                streamPresetEditor(
                    title: "Preset 1",
                    screenMode: $presetOneScreenMode,
                    width: $presetOneWidthInput,
                    height: $presetOneHeightInput,
                    fps: $presetOneFPSInput,
                    mouseMode: $presetOneMouseMode,
                    action: { saveStreamPreset(.one) }
                )

                Divider()

                streamPresetEditor(
                    title: "Preset 2",
                    screenMode: $presetTwoScreenMode,
                    width: $presetTwoWidthInput,
                    height: $presetTwoHeightInput,
                    fps: $presetTwoFPSInput,
                    mouseMode: $presetTwoMouseMode,
                    action: { saveStreamPreset(.two) }
                )

                Divider()

                streamPresetEditor(
                    title: "Preset 3",
                    screenMode: $presetThreeScreenMode,
                    width: $presetThreeWidthInput,
                    height: $presetThreeHeightInput,
                    fps: $presetThreeFPSInput,
                    mouseMode: $presetThreeMouseMode,
                    action: { saveStreamPreset(.three) }
                )

                Divider()

                streamPresetEditor(
                    title: "Preset 4",
                    screenMode: $presetFourScreenMode,
                    width: $presetFourWidthInput,
                    height: $presetFourHeightInput,
                    fps: $presetFourFPSInput,
                    mouseMode: $presetFourMouseMode,
                    action: { saveStreamPreset(.four) }
                )
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
        syncPresetInputs()
        syncInputSettings()
        loadWakeOnLANConfiguration()
    }

    private func syncPresetInputs() {
        syncPresetInput(.one)
        syncPresetInput(.two)
        syncPresetInput(.three)
        syncPresetInput(.four)
    }

    private func syncPresetInput(_ presetID: StreamPresetID) {
        let preset = coordinator.streamPreset(for: presetID)

        switch presetID {
        case .one:
            presetOneWidthInput = String(preset.resolution.width)
            presetOneHeightInput = String(preset.resolution.height)
            presetOneFPSInput = String(preset.fps)
            presetOneScreenMode = preset.screenMode
            presetOneMouseMode = preset.mouseMode
        case .two:
            presetTwoWidthInput = String(preset.resolution.width)
            presetTwoHeightInput = String(preset.resolution.height)
            presetTwoFPSInput = String(preset.fps)
            presetTwoScreenMode = preset.screenMode
            presetTwoMouseMode = preset.mouseMode
        case .three:
            presetThreeWidthInput = String(preset.resolution.width)
            presetThreeHeightInput = String(preset.resolution.height)
            presetThreeFPSInput = String(preset.fps)
            presetThreeScreenMode = preset.screenMode
            presetThreeMouseMode = preset.mouseMode
        case .four:
            presetFourWidthInput = String(preset.resolution.width)
            presetFourHeightInput = String(preset.resolution.height)
            presetFourFPSInput = String(preset.fps)
            presetFourScreenMode = preset.screenMode
            presetFourMouseMode = preset.mouseMode
        }
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

    private func saveStreamPreset(_ presetID: StreamPresetID) {
        do {
            let resolution = try resolutionFromInputs(
                width: presetWidthInput(for: presetID),
                height: presetHeightInput(for: presetID)
            )
            let fps = try fpsFromInput(presetFPSInput(for: presetID))
            try coordinator.saveStreamPreset(
                presetID,
                screenMode: presetScreenMode(for: presetID),
                resolution: resolution,
                fps: fps,
                mouseMode: presetMouseMode(for: presetID)
            )
            streamFeedbackMessage = "Preset \(presetLabel(for: presetID)) updated."
            streamFeedbackIsError = false
            syncPresetInput(presetID)
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

    private func streamPresetEditor(
        title: String,
        screenMode: Binding<StreamMode>,
        width: Binding<String>,
        height: Binding<String>,
        fps: Binding<String>,
        mouseMode: Binding<StreamMouseModePreference>,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)

                if coordinator.selectedStreamPresetID == presetID(for: title) {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("Screen Mode", selection: screenMode) {
                        Text("Windowed").tag(StreamMode.windowed)
                        Text("Fullscreen").tag(StreamMode.fullscreen)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mouse")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("Mouse Mode", selection: mouseMode) {
                        Text("Absolute").tag(StreamMouseModePreference.absolute)
                        Text("Raw").tag(StreamMouseModePreference.raw)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                settingField(title: "Width", placeholder: "1920", text: width)
                settingField(title: "Height", placeholder: "1080", text: height)
                settingField(title: "FPS", placeholder: "60", text: fps)

                VStack {
                    Spacer(minLength: 0)

                    Button("Apply", action: action)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func presetLabel(for presetID: StreamPresetID) -> String {
        switch presetID {
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        }
    }

    private func presetID(for title: String) -> StreamPresetID {
        switch title {
        case "Preset 1":
            return .one
        case "Preset 2":
            return .two
        case "Preset 3":
            return .three
        default:
            return .four
        }
    }

    private func presetWidthInput(for presetID: StreamPresetID) -> String {
        switch presetID {
        case .one:
            return presetOneWidthInput
        case .two:
            return presetTwoWidthInput
        case .three:
            return presetThreeWidthInput
        case .four:
            return presetFourWidthInput
        }
    }

    private func presetHeightInput(for presetID: StreamPresetID) -> String {
        switch presetID {
        case .one:
            return presetOneHeightInput
        case .two:
            return presetTwoHeightInput
        case .three:
            return presetThreeHeightInput
        case .four:
            return presetFourHeightInput
        }
    }

    private func presetFPSInput(for presetID: StreamPresetID) -> String {
        switch presetID {
        case .one:
            return presetOneFPSInput
        case .two:
            return presetTwoFPSInput
        case .three:
            return presetThreeFPSInput
        case .four:
            return presetFourFPSInput
        }
    }

    private func presetScreenMode(for presetID: StreamPresetID) -> StreamMode {
        switch presetID {
        case .one:
            return presetOneScreenMode
        case .two:
            return presetTwoScreenMode
        case .three:
            return presetThreeScreenMode
        case .four:
            return presetFourScreenMode
        }
    }

    private func presetMouseMode(for presetID: StreamPresetID) -> StreamMouseModePreference {
        switch presetID {
        case .one:
            return presetOneMouseMode
        case .two:
            return presetTwoMouseMode
        case .three:
            return presetThreeMouseMode
        case .four:
            return presetFourMouseMode
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
