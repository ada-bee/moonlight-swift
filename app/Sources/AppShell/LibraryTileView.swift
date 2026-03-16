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

    struct FPSOption: Hashable, Identifiable {
        let fps: Int

        var id: Int {
            fps
        }
    }

    let application: HostApplication
    let launchesFullscreen: Bool
    let usesRawMouse: Bool
    let supportedResolutions: [MVPConfiguration.Video.Resolution]
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
    let onResolutionChange: (MVPConfiguration.Video.Resolution) -> Void
    let onFPSChange: (Int) -> Void

    private static let fpsOptions: [FPSOption] = [
        .init(fps: 30),
        .init(fps: 60),
        .init(fps: 90),
        .init(fps: 120)
    ]

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

                    Picker("Resolution", selection: resolutionBinding) {
                        ForEach(resolutionOptions) { option in
                            Text(option.label)
                                .tag(option)
                        }

                        if resolutionOptions.contains(selectedResolutionOption) == false {
                            Text(selectedResolutionOption.label)
                                .tag(selectedResolutionOption)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 148)
                    .disabled(launchesFullscreen)

                    Picker("Refresh Rate", selection: fpsBinding) {
                        ForEach(Self.fpsOptions) { option in
                            Text("\(option.fps) Hz")
                                .tag(option)
                        }

                        if Self.fpsOptions.contains(selectedFPSOption) == false {
                            Text("\(selectedFPSOption.fps) Hz")
                                .tag(selectedFPSOption)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 108)
                    .disabled(launchesFullscreen)
                }

                if launchesFullscreen {
                    Text("Fullscreen uses the display's native resolution and refresh rate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var resolutionOptions: [ResolutionOption] {
        supportedResolutions.map {
            ResolutionOption(
                resolution: $0,
                label: "\($0.width) x \($0.height)"
            )
        }
    }

    private var selectedResolutionOption: ResolutionOption {
        resolutionOptions.first(where: {
            $0.resolution == selectedResolution
        }) ?? .init(
            resolution: selectedResolution,
            label: "\(selectedResolution.width) x \(selectedResolution.height)"
        )
    }

    private var selectedFPSOption: FPSOption {
        Self.fpsOptions.first(where: { $0.fps == selectedFPS }) ?? .init(fps: selectedFPS)
    }

    private var resolutionBinding: Binding<ResolutionOption> {
        Binding(
            get: { selectedResolutionOption },
            set: { newValue in
                onResolutionChange(newValue.resolution)
            }
        )
    }

    private var fpsBinding: Binding<FPSOption> {
        Binding(
            get: { selectedFPSOption },
            set: { newValue in
                onFPSChange(newValue.fps)
            }
        )
    }
}
