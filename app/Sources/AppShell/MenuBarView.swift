import AppKit
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
        VStack(alignment: .leading, spacing: 12) {
            sessionSection
            compactControlsSection
            utilitySection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionSection: some View {
        sectionContainer {
            VStack(alignment: .leading, spacing: 12) {
                switch coordinator.streamActivityState {
                case .streaming, .paused:
                    runningSessionContent
                case .inactive:
                    inactiveSessionContent
                }

                if let message = coordinator.libraryActionError {
                    Text(message)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var runningSessionContent: some View {
        HStack(alignment: .center, spacing: 12) {
            posterPlaceholder

            VStack(alignment: .leading, spacing: 4) {
                Text(coordinator.runningApplicationTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(streamInfoText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(sessionStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sessionStatusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if coordinator.canPauseRunningApplication {
                    actionGlyphButton(
                        systemImage: "pause.fill",
                        title: "Pause",
                        action: coordinator.pauseRunningApplication
                    )
                }

                if coordinator.canResumeRunningApplication {
                    actionGlyphButton(
                        systemImage: "play.fill",
                        title: "Resume",
                        action: coordinator.resumeRunningApplication
                    )
                }

                if coordinator.canStopRunningApplication {
                    actionGlyphButton(
                        systemImage: "stop.fill",
                        title: "Stop",
                        role: .destructive,
                        action: coordinator.stopRunningApplication
                    )
                }
            }
        }
    }

    private var inactiveSessionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch coordinator.hostAvailabilityState {
            case .unconfigured:
                statusRow(
                    icon: "display.trianglebadge.exclamationmark",
                    title: "No Sunshine host configured",
                    detail: "Open Settings to pair a host before starting a session."
                )

            case .checking:
                statusRow(
                    icon: "bolt.horizontal.circle",
                    title: coordinator.launchInProgress ? "Connecting to Sunshine host" : "Checking Sunshine host",
                    detail: coordinator.launchInProgress
                        ? "Starting the remote desktop session."
                        : "Refreshing host availability and running state."
                )

            case .reachable:
                statusRow(
                    icon: "checkmark.circle.fill",
                    title: "Sunshine host ready",
                    detail: "No active session"
                )

            case .unreachable:
                statusRow(
                    icon: "wifi.exclamationmark",
                    title: "Sunshine host not reachable",
                    detail: unreachableDetailText
                )

                if coordinator.hasWakeOnLANConfiguration {
                    Button("Send Wake Packet", action: coordinator.sendWakeOnLANMagicPacket)
                        .buttonStyle(.borderedProminent)
                }
            }

            if canRunPrimaryAction {
                Button(primaryActionTitle, action: handlePrimaryAction)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var compactControlsSection: some View {
        sectionContainer {
            HStack(spacing: 10) {
                Menu {
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
                } label: {
                    sectionMenuLabel(title: "Display", systemImage: "display")
                }
                .menuStyle(.borderlessButton)
                .disabled(!isStreamMenuAvailable)

                Menu {
                    Toggle("Direct Mouse Input", isOn: rawMouseInputBinding)
                        .disabled(!isStreamMenuAvailable || coordinator.activeStreamMouseMode == nil || coordinator.launchInProgress || coordinator.stopInProgress)
                } label: {
                    sectionMenuLabel(title: "Input", systemImage: "cursorarrow.motionlines")
                }
                .menuStyle(.borderlessButton)
                .disabled(!isStreamMenuAvailable)

                Spacer(minLength: 0)
            }
        }
    }

    private var utilitySection: some View {
        sectionContainer {
            VStack(alignment: .leading, spacing: 6) {
                Button("Refresh Host", action: coordinator.refreshLibrary)
                    .disabled(coordinator.pairedHost == nil || coordinator.launchInProgress || coordinator.stopInProgress)

                Button("Settings...", action: showSettings)

                Button("Quit") {
                    coordinator.terminateApplication()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func sectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func sectionMenuLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
    }

    private func actionGlyphButton(
        systemImage: String,
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .background(.thinMaterial, in: Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .help(title)
    }

    private func statusRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unreachableDetailText: String {
        if case let .unreachable(message) = coordinator.hostAvailabilityState,
           !message.isEmpty {
            return message
        }

        return "The paired host did not answer the latest availability check."
    }

    private var sessionStatusText: String {
        switch coordinator.streamActivityState {
        case .inactive:
            return "Idle"
        case .paused:
            return "Paused"
        case .streaming:
            return "Streaming"
        }
    }

    private var sessionStatusColor: Color {
        switch coordinator.streamActivityState {
        case .inactive:
            return .secondary
        case .paused:
            return Color(nsColor: .systemOrange)
        case .streaming:
            return Color(nsColor: .systemGreen)
        }
    }

    private var streamInfoText: String {
        let resolution = coordinator.currentRunningApplicationResolution
            ?? coordinator.activeStreamResolution
        let fps = coordinator.currentRunningApplicationFPS
            ?? coordinator.activeStreamFPS

        if let resolution, let fps {
            return "\(resolution.width) x \(resolution.height) @ \(fps)"
        }

        if let resolution {
            return "\(resolution.width) x \(resolution.height)"
        }

        if let fps {
            return "\(fps) Hz"
        }

        return "Stream details unavailable"
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
