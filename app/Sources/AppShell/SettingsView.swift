import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Reset pairing on the next app launch. This keeps the main window minimal while preserving the existing stream path.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Button("Reset Pairing On Next Launch", role: .destructive) {
                coordinator.markPairingResetOnNextLaunch()
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
    }
}
