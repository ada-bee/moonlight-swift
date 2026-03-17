import AppKit
import MoonlightCore
import SwiftUI

struct LibraryTileView: View {
    let application: HostApplication
    let playDisabled: Bool
    let pauseDisabled: Bool
    let stopDisabled: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            poster
                .frame(width: 78, height: 117)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(application.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if application.isRunning {
                        runningBadge
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    controlButton(systemName: "play.fill", title: "Play", disabled: playDisabled, action: onPlay)
                    controlButton(systemName: "pause.fill", title: "Pause", disabled: pauseDisabled, action: onPause)
                    controlButton(systemName: "stop.fill", title: "Stop", disabled: stopDisabled, action: onStop)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var poster: some View {
        if let posterURL = application.posterURL,
           let nsImage = NSImage(contentsOf: posterURL)
        {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))

                Image(systemName: "play.tv")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runningBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            Text("Running")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.green)
    }

    private func controlButton(systemName: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.bordered)
        .help(title)
        .disabled(disabled)
    }
}
