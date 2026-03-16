import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        ZStack {
            switch model.mainContentState {
            case .library:
                LibraryView(model: model)
            case .loading:
                LoadingStateView(model: model)
            case .noHostConfigured:
                HostStatusView(
                    message: "No Sunshine host configured. Add one in Settings and try again.",
                    onRetry: model.retryConnection
                )
            case .connectionIssue:
                HostStatusView(
                    message: "Unable to connect to Sunshine. Verify host configuration in Settings and try again.",
                    onRetry: model.retryConnection
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LoadingStateView: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()

            Text(loadingTitle)
                .font(.headline)

            if let detailText = loadingDetailText {
                Text(detailText)
                    .foregroundStyle(.secondary)
            }

            if let pin = model.pairingPIN {
                Text(pin)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var loadingTitle: String {
        if model.pairingInProgress {
            return "Pairing with Sunshine..."
        }

        return "Loading library..."
    }

    private var loadingDetailText: String? {
        if let pairingStatusText = model.pairingStatusText {
            return pairingStatusText
        }

        return "Fetching the host app list and refreshing poster art."
    }
}

private struct HostStatusView: View {
    @Environment(\.openSettings) private var openSettings

    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

                Button("Settings", action: showSettings)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
