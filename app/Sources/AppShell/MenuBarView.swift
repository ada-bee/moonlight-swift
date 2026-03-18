import MoonlightCore
import SwiftUI

private enum MenuBarIconAsset {
    static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "display", accessibilityDescription: "GameStream") ?? NSImage()
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Divider()

            Button(primaryActionTitle, action: handlePrimaryAction)
                .disabled(!canRunPrimaryAction)

            if coordinator.canResumeRunningApplication {
                Button("Resume", action: coordinator.resumeRunningApplication)
            }

            if coordinator.canPauseRunningApplication {
                Button("Pause", action: coordinator.pauseRunningApplication)
            }

            if coordinator.canStopRunningApplication {
                Button("Stop", action: coordinator.stopRunningApplication)
            }

            Divider()

            Menu("Display") {
                Toggle("Fullscreen", isOn: fullscreenBinding)
                    .disabled(!isStreamMenuAvailable || coordinator.activeStreamScreenMode == nil || coordinator.launchInProgress || coordinator.stopInProgress)

                Divider()

                Menu("Resolution") {
                    ForEach(resolutionOptions, id: \.self) { option in
                        Toggle(option.label, isOn: resolutionBinding(for: option.resolution))
                    }
                }
                .disabled(!isStreamMenuAvailable || !isResolutionMenuEnabled)

                Menu("Frame Rate") {
                    ForEach(fpsOptions, id: \.self) { option in
                        Toggle(option.label, isOn: fpsBinding(for: option.fps))
                    }
                }
                .disabled(!isStreamMenuAvailable || !isResolutionMenuEnabled)
            }
            .disabled(!isStreamMenuAvailable)

            Menu("Input") {
                Toggle("Direct Mouse Input", isOn: rawMouseInputBinding)
                    .disabled(!isStreamMenuAvailable || coordinator.activeStreamMouseMode == nil || coordinator.launchInProgress || coordinator.stopInProgress)
            }
            .disabled(!isStreamMenuAvailable)

            Divider()

            Button("Refresh Host", action: coordinator.refreshLibrary)
                .disabled(coordinator.pairedHost == nil || coordinator.launchInProgress || coordinator.stopInProgress)

            Button("Settings...", action: showSettings)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.headline)

            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let message = coordinator.libraryActionError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 8)
    }

    private var statusTitle: String {
        switch coordinator.streamActivityState {
        case .inactive:
            return coordinator.launchInProgress ? "Connecting..." : "Desktop ready"
        case .paused:
            return "Desktop paused"
        case .streaming:
            return "Desktop streaming"
        }
    }

    private var statusDetail: String {
        if coordinator.pairedHost == nil {
            return "Pair a Sunshine host in Settings to begin."
        }

        switch coordinator.streamActivityState {
        case .inactive:
            if coordinator.launchInProgress {
                return "Starting the remote desktop stream."
            }
            return "Launch the Windows desktop from the menu bar."
        case .paused:
            return "The host desktop is still running without an active stream."
        case .streaming:
            return "The active stream window is available on your desktop."
        }
    }

    private var primaryActionTitle: String {
        coordinator.primaryActionTitle
    }

    private var canRunPrimaryAction: Bool {
        switch coordinator.streamActivityState {
        case .inactive:
            return coordinator.canLaunchDesktop
        case .paused:
            return coordinator.canResumeRunningApplication || coordinator.canLaunchDesktop
        case .streaming:
            return coordinator.activeStreamApplicationID != nil
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

    private var isStreamMenuAvailable: Bool {
        coordinator.activeStreamApplicationID != nil
    }

    private func handlePrimaryAction() {
        switch coordinator.streamActivityState {
        case .inactive:
            coordinator.launchDesktop()
        case .paused:
            if coordinator.canResumeRunningApplication {
                coordinator.resumeRunningApplication()
            } else {
                coordinator.launchDesktop()
            }
        case .streaming:
            coordinator.presentActiveStreamWindow()
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

struct MenuBarStatusIcon: View {
    let streamActivityState: AppCoordinator.StreamActivityState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: MenuBarIconAsset.image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                    )
                    .offset(x: 2, y: 1)
            }
        }
        .frame(width: 20, height: 18)
    }

    private var dotColor: Color? {
        switch streamActivityState {
        case .inactive:
            return nil
        case .paused:
            return Color(nsColor: .systemOrange)
        case .streaming:
            return Color(nsColor: .systemGreen)
        }
    }
}
