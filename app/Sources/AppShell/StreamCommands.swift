import MoonlightCore
import SwiftUI

struct StreamCommands: Commands {
    @ObservedObject var coordinator: AppCoordinator

    private struct ResolutionOption: Hashable, Identifiable {
        let resolution: MVPConfiguration.Video.Resolution

        var id: String {
            "\(resolution.width)x\(resolution.height)"
        }

        var label: String {
            "\(resolution.width) x \(resolution.height)"
        }
    }

    private struct FPSOption: Hashable, Identifiable {
        let fps: Int

        var id: Int {
            fps
        }

        var label: String {
            "\(fps) Hz"
        }
    }

    private static let standardFPSOptions: [FPSOption] = [
        .init(fps: 30),
        .init(fps: 60),
        .init(fps: 90),
        .init(fps: 120)
    ]

    var body: some Commands {
        CommandMenu("Stream") {
            Toggle("Fullscreen", isOn: fullscreenBinding)
            .disabled(coordinator.activeStreamScreenMode == nil || coordinator.launchInProgress || coordinator.stopInProgress)

            Menu("Resolution") {
                ForEach(resolutionOptions, id: \.self) { option in
                    Toggle(option.label, isOn: resolutionBinding(for: option.resolution))
                }
            }
            .disabled(!isResolutionMenuEnabled)

            Menu("Frame Rate") {
                ForEach(fpsOptions, id: \.self) { option in
                    Toggle(option.label, isOn: fpsBinding(for: option.fps))
                }
            }
            .disabled(!isResolutionMenuEnabled)

            Divider()

            Toggle("Direct Mouse Input", isOn: rawMouseInputBinding)
                .disabled(coordinator.activeStreamMouseMode == nil || coordinator.launchInProgress || coordinator.stopInProgress)
        }
    }

    private var rawMouseInputBinding: Binding<Bool> {
        Binding(
            get: { coordinator.activeStreamMouseMode == .raw },
            set: { isSelected in
                coordinator.setActiveStreamMouseMode(isSelected ? .raw : .absolute)
            }
        )
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { coordinator.activeStreamScreenMode == .fullscreen },
            set: { isSelected in
                coordinator.setActiveStreamScreenMode(isSelected ? .fullscreen : .windowed)
            }
        )
    }

    private func resolutionBinding(for resolution: MVPConfiguration.Video.Resolution) -> Binding<Bool> {
        Binding(
            get: { coordinator.activeStreamResolution == resolution },
            set: { isSelected in
                guard isSelected else {
                    return
                }

                coordinator.setActiveStreamResolution(resolution)
            }
        )
    }

    private func fpsBinding(for fps: Int) -> Binding<Bool> {
        Binding(
            get: { coordinator.activeStreamFPS == fps },
            set: { isSelected in
                guard isSelected else {
                    return
                }

                coordinator.setActiveStreamFPS(fps)
            }
        )
    }

    private var resolutionOptions: [ResolutionOption] {
        var options = coordinator.settings.video.supportedResolutions.map { ResolutionOption(resolution: $0) }
        if let activeResolution = coordinator.activeStreamResolution,
           options.contains(where: { $0.resolution == activeResolution }) == false {
            options.append(ResolutionOption(resolution: activeResolution))
            options.sort { lhs, rhs in
                let lhsPixels = lhs.resolution.width * lhs.resolution.height
                let rhsPixels = rhs.resolution.width * rhs.resolution.height

                if lhsPixels != rhsPixels {
                    return lhsPixels > rhsPixels
                }

                if lhs.resolution.width != rhs.resolution.width {
                    return lhs.resolution.width > rhs.resolution.width
                }

                return lhs.resolution.height > rhs.resolution.height
            }
        }
        return options
    }

    private var fpsOptions: [FPSOption] {
        var options = Self.standardFPSOptions
        if let activeFPS = coordinator.activeStreamFPS,
           options.contains(where: { $0.fps == activeFPS }) == false {
            options.append(.init(fps: activeFPS))
            options.sort { $0.fps < $1.fps }
        }
        return options
    }

    private var isResolutionMenuEnabled: Bool {
        coordinator.activeStreamSupportsResolutionSelection
            && coordinator.activeStreamScreenMode == .windowed
            && !coordinator.launchInProgress
            && !coordinator.stopInProgress
    }
}
