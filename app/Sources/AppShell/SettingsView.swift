import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator

    @State private var macAddress = ""
    @State private var broadcastAddress = ""
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 10) {
                Text("Wake On LAN")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text("Send a Wake-on-LAN magic packet each time the app launches. Enter the host MAC address manually because Sunshine pairing does not expose it here.")
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
                    .disabled(!hasPairedHost || trimmedMACAddress.isEmpty)
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(feedbackIsError ? Color(nsColor: .systemRed) : .secondary)
                }

                if !hasPairedHost {
                    Text("Pair with a host before saving Wake-on-LAN settings.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Reset pairing on the next app launch. This keeps the main window minimal while preserving the existing stream path.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Button("Reset Pairing On Next Launch", role: .destructive) {
                coordinator.markPairingResetOnNextLaunch()
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
        .onAppear(perform: loadWakeOnLANConfiguration)
        .onReceive(coordinator.$pairedHost) { _ in
            loadWakeOnLANConfiguration()
        }
    }

    private var hasPairedHost: Bool {
        coordinator.pairedHost != nil
    }

    private var trimmedMACAddress: String {
        macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadWakeOnLANConfiguration() {
        if let configuration = coordinator.pairedHost?.wakeOnLANConfiguration {
            macAddress = configuration.macAddress
            broadcastAddress = configuration.broadcastAddress ?? ""
        } else {
            macAddress = ""
            broadcastAddress = ""
        }

        feedbackMessage = nil
        feedbackIsError = false
    }

    private func saveWakeOnLANConfiguration() {
        do {
            try coordinator.saveWakeOnLANConfiguration(macAddress: macAddress, broadcastAddress: broadcastAddress)
            loadWakeOnLANConfiguration()
            feedbackMessage = "Wake-on-LAN will be sent when GameStream launches."
            feedbackIsError = false
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }

    private func clearWakeOnLANConfiguration() {
        do {
            try coordinator.clearWakeOnLANConfiguration()
            loadWakeOnLANConfiguration()
            feedbackMessage = "Wake-on-LAN settings cleared."
            feedbackIsError = false
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
    }
}
