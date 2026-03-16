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
    @State private var resetInProgress = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                sunshineHostSection
                wakeOnLANSection

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadState)
        .onReceive(coordinator.$settings) { _ in
            hostInput = coordinator.settings.host?.displayString ?? ""
            clearHostFeedbackIfNeeded()
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
            Text("Sunshine Host")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("Pair here instead of the main window. Enter the Sunshine host as ip:port, then pair or update the current host.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let pin = pairingPIN {
                Text(pin)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .padding(.top, 2)
            }

            if let hostFeedbackMessage {
                Text(hostFeedbackMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(hostFeedbackIsError ? Color(nsColor: .systemRed) : .secondary)
            }
        }
    }

    private var wakeOnLANSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wake On LAN")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("Add or change the host MAC address used for Wake-on-LAN packets. Sunshine pairing does not expose it here, so enter it manually.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(wakeOnLANFeedbackIsError ? Color(nsColor: .systemRed) : .secondary)
            }

            if !hasPairedHost {
                Text("Pair with a host before saving Wake-on-LAN settings.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pairedHostSummary: some View {
        if let pairedHost = coordinator.pairedHost {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current paired host")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(pairedHost.host.displayString)
                    .font(.system(.body, design: .monospaced))

                if let macAddress = pairedHost.wakeOnLANConfiguration?.macAddress {
                    Text("Wake-on-LAN MAC: \(macAddress)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        } else if hasConfiguredHost {
            Text("No active pairing is stored for the configured host yet.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            Text("No Sunshine host is configured yet.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
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
}

private extension AppCoordinator.PairingState {
    var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }

        return false
    }
}
