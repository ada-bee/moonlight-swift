import AppKit
import MoonlightCore
import SwiftUI

struct LibraryTileView: View {
    struct ResolutionOption: Hashable, Identifiable {
        let resolution: MVPConfiguration.Video.Resolution
        let label: String

        var id: String {
            "\(resolution.width)x\(resolution.height)"
        }
    }

    let application: HostApplication
    let launchesFullscreen: Bool
    let selectedResolution: MVPConfiguration.Video.Resolution
    let playDisabled: Bool
    let pauseDisabled: Bool
    let stopDisabled: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onFullscreenChange: (Bool) -> Void
    let onResolutionChange: (MVPConfiguration.Video.Resolution) -> Void

    private static let resolutionOptions: [ResolutionOption] = [
        .init(resolution: .init(width: 1280, height: 720), label: "1280 x 720"),
        .init(resolution: .init(width: 1600, height: 900), label: "1600 x 900"),
        .init(resolution: .init(width: 1920, height: 1080), label: "1920 x 1080"),
        .init(resolution: .init(width: 2560, height: 1440), label: "2560 x 1440"),
        .init(resolution: .init(width: 3840, height: 2160), label: "3840 x 2160")
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            thumbnail
                .frame(width: 208, height: 117)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Text(application.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if application.isRunning {
                        runningBadge
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    controlButton(systemName: "play.fill", title: "Play", disabled: playDisabled, action: onPlay)
                    controlButton(systemName: "pause.fill", title: "Pause", disabled: pauseDisabled, action: onPause)
                    controlButton(systemName: "stop.fill", title: "Stop", disabled: stopDisabled, action: onStop)

                    Divider()
                        .frame(height: 26)

                    Toggle(isOn: fullscreenBinding) {
                        Text("Full Screen")
                            .font(.subheadline)
                    }
                    .toggleStyle(.checkbox)
                    .fixedSize()

                    Picker("Resolution", selection: resolutionBinding) {
                        ForEach(Self.resolutionOptions) { option in
                            Text(option.label)
                                .tag(option.resolution)
                        }

                        if Self.resolutionOptions.contains(where: { $0.resolution == selectedResolution }) == false {
                            Text("\(selectedResolution.width) x \(selectedResolution.height)")
                                .tag(selectedResolution)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(launchesFullscreen)
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
    private var thumbnail: some View {
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
                    .font(.system(size: 34, weight: .medium))
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

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { launchesFullscreen },
            set: { newValue in
                onFullscreenChange(newValue)
            }
        )
    }

    private var resolutionBinding: Binding<MVPConfiguration.Video.Resolution> {
        Binding(
            get: { selectedResolution },
            set: { newValue in
                onResolutionChange(newValue)
            }
        )
    }
}
