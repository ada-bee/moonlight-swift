import AppKit
import MoonlightCore
import SwiftUI

struct LibraryTileView: View {
    struct DisplayModeOption: Hashable, Identifiable {
        let resolution: MVPConfiguration.Video.Resolution
        let fps: Int
        let label: String

        var id: String {
            "\(resolution.width)x\(resolution.height)@\(fps)"
        }
    }

    let application: HostApplication
    let launchesFullscreen: Bool
    let usesRawMouse: Bool
    let selectedResolution: MVPConfiguration.Video.Resolution
    let selectedFPS: Int
    let playDisabled: Bool
    let pauseDisabled: Bool
    let stopDisabled: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onFullscreenChange: (Bool) -> Void
    let onRawMouseChange: (Bool) -> Void
    let onDisplayModeChange: (MVPConfiguration.Video.Resolution, Int) -> Void

    private static let displayModeOptions: [DisplayModeOption] = [
        .init(resolution: .init(width: 3840, height: 1600), fps: 120, label: "3840 x 1600 @ 120"),
        .init(resolution: .init(width: 2440, height: 1520), fps: 120, label: "2440 x 1520 @ 120"),
        .init(resolution: .init(width: 2560, height: 1440), fps: 120, label: "2560 x 1440 @ 120"),
        .init(resolution: .init(width: 1680, height: 1050), fps: 120, label: "1680 x 1050 @ 120"),
        .init(resolution: .init(width: 1440, height: 900), fps: 60, label: "1440 x 900 @ 60"),
        .init(resolution: .init(width: 1280, height: 800), fps: 60, label: "1280 x 800 @ 60")
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

                    Toggle(isOn: rawMouseBinding) {
                        Text("Raw Mouse")
                            .font(.subheadline)
                    }
                    .toggleStyle(.checkbox)
                    .fixedSize()

                    Picker("Display Mode", selection: displayModeBinding) {
                        ForEach(Self.displayModeOptions) { option in
                            Text(option.label)
                                .tag(option)
                        }

                        if Self.displayModeOptions.contains(selectedDisplayMode) == false {
                            Text(selectedDisplayMode.label)
                                .tag(selectedDisplayMode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
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

    private var rawMouseBinding: Binding<Bool> {
        Binding(
            get: { usesRawMouse },
            set: { newValue in
                onRawMouseChange(newValue)
            }
        )
    }

    private var selectedDisplayMode: DisplayModeOption {
        Self.displayModeOptions.first(where: {
            $0.resolution == selectedResolution && $0.fps == selectedFPS
        }) ?? .init(
            resolution: selectedResolution,
            fps: selectedFPS,
            label: "\(selectedResolution.width) x \(selectedResolution.height) @ \(selectedFPS)"
        )
    }

    private var displayModeBinding: Binding<DisplayModeOption> {
        Binding(
            get: { selectedDisplayMode },
            set: { newValue in
                onDisplayModeChange(newValue.resolution, newValue.fps)
            }
        )
    }
}
