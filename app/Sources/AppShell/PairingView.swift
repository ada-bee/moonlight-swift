import SwiftUI

struct PairingView: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Moonlight")
                    .font(.largeTitle)
                    .foregroundStyle(.primary)

                Text("Enter the Sunshine host as ip:port to begin pairing.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("192.168.1.10:47989", text: $model.hostInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        model.startPairing()
                    }

                Button(model.pairingInProgress ? "Pairing..." : "Start Pairing", action: model.startPairing)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                .disabled(model.hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pairingInProgress)
            }

            if let statusText = model.pairingStatusText {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let pairingPIN = model.pairingPIN {
                Text(pairingPIN)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
            }

            if let pairingError = model.pairingError {
                Text(pairingError)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(32)
    }
}
