import MoonlightCore
import SwiftUI

struct StreamCommands: Commands {
    @ObservedObject var coordinator: AppCoordinator

    private struct ResolutionOption: Hashable, Identifiable {
        let resolution: StreamConfiguration.Video.Resolution

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
            Button("Show Stream") {
                coordinator.handlePrimaryActivationRequest()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!coordinator.canLaunchDesktop && !coordinator.canResumeRunningApplication && coordinator.activeSessionController == nil)

            Button("Hide Stream") {
                coordinator.hideActiveStreamWindow()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(!coordinator.canHideActiveStreamWindow)

            Button("Stop Session") {
                coordinator.stopSessionAndHideWindow()
            }
            .keyboardShortcut("w", modifiers: [.control, .shift])
            .disabled(!coordinator.canStopSessionAndHideWindow)

            Button("Quit GameStream") {
                coordinator.terminateApplication()
            }
            .keyboardShortcut("q", modifiers: [.command])

            Divider()

            Toggle("Fullscreen", isOn: fullscreenBinding)
            .disabled(coordinator.launchInProgress || coordinator.stopInProgress)

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
        }

        CommandGroup(replacing: .saveItem) {
            Button("Hide Stream") {
                coordinator.hideActiveStreamWindow()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(!coordinator.canHideActiveStreamWindow)
        }
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { coordinator.streamMode == .fullscreen },
            set: { isSelected in
                coordinator.setStreamMode(isSelected ? .fullscreen : .windowed)
            }
        )
    }

    private func resolutionBinding(for resolution: StreamConfiguration.Video.Resolution) -> Binding<Bool> {
        Binding(
            get: { coordinator.windowedStreamResolution == resolution },
            set: { isSelected in
                guard isSelected else {
                    return
                }

                coordinator.setWindowedStreamResolution(resolution)
            }
        )
    }

    private func fpsBinding(for fps: Int) -> Binding<Bool> {
        Binding(
            get: { coordinator.windowedStreamFPS == fps },
            set: { isSelected in
                guard isSelected else {
                    return
                }

                coordinator.setWindowedStreamFPS(fps)
            }
        )
    }

    private var resolutionOptions: [ResolutionOption] {
        var options = coordinator.settings.video.supportedResolutions.map { ResolutionOption(resolution: $0) }
        let selectedResolution = coordinator.windowedStreamResolution
        if options.contains(where: { $0.resolution == selectedResolution }) == false {
            options.append(ResolutionOption(resolution: selectedResolution))
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
        if options.contains(where: { $0.fps == coordinator.windowedStreamFPS }) == false {
            options.append(.init(fps: coordinator.windowedStreamFPS))
            options.sort { $0.fps < $1.fps }
        }
        return options
    }

    private var isResolutionMenuEnabled: Bool {
        coordinator.streamMode == .windowed
            && !coordinator.launchInProgress
            && !coordinator.stopInProgress
    }
}
