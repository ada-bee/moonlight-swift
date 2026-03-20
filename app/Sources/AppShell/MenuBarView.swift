import AppKit
import MoonlightCore
import SwiftUI

private enum MenuBarIconAsset {
    static let image: NSImage = {
        guard let url = PackageResourceBundle.executableTarget?.url(forResource: "MenuBarIcon", withExtension: "svg"),
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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = coordinator.libraryActionError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }

            sessionSection
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            coordinator.menuBarDidOpen()
        }
    }

    private var sessionSection: some View {
        menuPanel {
            switch coordinator.streamActivityState {
            case .streaming, .paused:
                runningSessionContent
            case .inactive:
                inactiveSessionContent
            }
        }
    }

    private var runningSessionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionStatusText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(sessionStatusColor)
                        .lineLimit(1)

                    Text(streamInfoText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                streamModeToggle
            }

            if hasTransportControls {
                HStack(spacing: 10) {
                    if coordinator.canPauseRunningApplication {
                        actionButton(
                            systemImage: "pause.fill",
                            title: "Pause",
                            prominence: .caution,
                            action: coordinator.pauseRunningApplication
                        )
                    }

                    if coordinator.canResumeRunningApplication {
                        actionButton(
                            systemImage: "play.fill",
                            title: "Resume",
                            prominence: .positive,
                            action: coordinator.resumeRunningApplication
                        )
                    }

                    if coordinator.canStopRunningApplication {
                        actionButton(
                            systemImage: "stop.fill",
                            title: "Stop",
                            role: .destructive,
                            prominence: .destructive,
                            action: coordinator.stopRunningApplication
                        )
                    }

                    utilitySection
                }
            }

        }
    }

    private var inactiveSessionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hostStatusText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(hostStatusColor)

                    Text(hostDetailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                streamModeToggle
            }

            HStack(spacing: 10) {
                switch coordinator.hostAvailabilityState {
                case .unreachable:
                    if coordinator.hasWakeOnLANConfiguration {
                        actionButton(
                            systemImage: "wake.circle",
                            title: "Send Wake Packet",
                            action: coordinator.sendWakeOnLANMagicPacket
                        )
                    }

                case .unconfigured, .checking, .reachable:
                    EmptyView()
                }

                if canRunPrimaryAction {
                    actionButton(
                        systemImage: primaryActionSymbol,
                        title: primaryActionButtonTitle,
                        prominence: .caution,
                        action: handlePrimaryAction
                    )
                }

                utilitySection
            }
        }
    }

    private var utilitySection: some View {
        HStack(spacing: 8) {
            SettingsLink {
                utilityIconLabel(title: "Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: coordinator.terminateApplication) {
                utilityIconLabel(title: "Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
    }

    private func utilityIconLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .frame(width: 34, height: 34)
            .glassEffect(.clear, in: Circle())
    }

    private var streamModeToggle: some View {
        Toggle(isOn: fullscreenBinding) {
            Image(systemName: streamModeGlyphSymbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 20, height: 20)
                .padding(.trailing, 4)
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .help(streamModeHelpText)
        .disabled(coordinator.launchInProgress || coordinator.stopInProgress)
        .accessibilityLabel(streamModeAccessibilityLabel)
    }

    private func menuPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(
        systemImage: String,
        title: String,
        role: ButtonRole? = nil,
        prominence: ActionButtonProminence = .standard,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .font(.body.weight(.semibold))
        .layoutPriority(1)
        .tint(buttonTint(for: prominence))
        .help(title)
    }

    private var hasTransportControls: Bool {
        coordinator.canPauseRunningApplication || coordinator.canResumeRunningApplication || coordinator.canStopRunningApplication
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

    private var hostStatusText: String {
        switch coordinator.hostAvailabilityState {
        case .unconfigured, .unreachable:
            return "Offline"
        case .checking:
            return coordinator.launchInProgress ? "Streaming" : "Ready"
        case .reachable:
            return "Ready"
        }
    }

    private var hostStatusColor: Color {
        switch coordinator.hostAvailabilityState {
        case .unconfigured, .unreachable:
            return .secondary
        case .checking:
            return coordinator.launchInProgress ? Color(nsColor: .systemGreen) : .secondary
        case .reachable:
            return Color(nsColor: .systemGreen)
        }
    }

    private var hostDetailText: String {
        switch coordinator.hostAvailabilityState {
        case .unconfigured:
            return "Open Settings to pair a host before starting a session."
        case .checking:
            return coordinator.launchInProgress
                ? "Starting the remote desktop session."
                : "Refreshing host availability and running state."
        case .reachable:
            return "No active session"
        case .unreachable:
            return unreachableDetailText
        }
    }

    private var streamInfoText: String {
        let resolution = coordinator.currentStreamResolution
        let fps = coordinator.currentStreamFPS

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

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { coordinator.streamMode == .fullscreen },
            set: { isSelected in
                coordinator.setStreamMode(isSelected ? .fullscreen : .windowed)
            }
        )
    }

    private var primaryActionTitle: String {
        coordinator.primaryActionTitle
    }

    private var primaryActionButtonTitle: String {
        switch primaryActionTitle {
        case "Launch Desktop":
            return "Launch"
        default:
            return primaryActionTitle
        }
    }

    private var primaryActionSymbol: String {
        switch coordinator.streamActivityState {
        case .inactive:
            return "desktopcomputer"
        case .paused:
            return coordinator.canResumeRunningApplication ? "play.fill" : "desktopcomputer"
        case .streaming:
            return "macwindow.on.rectangle"
        }
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

    private func handlePrimaryAction() {
        switch coordinator.streamActivityState {
        case .inactive:
            coordinator.launchDesktop()
            dismiss()
        case .paused:
            if coordinator.canResumeRunningApplication {
                coordinator.resumeRunningApplication()
                dismiss()
            } else {
                coordinator.launchDesktop()
                dismiss()
            }
        case .streaming:
            coordinator.presentActiveStreamWindow()
        }
    }

    private func buttonTint(for prominence: ActionButtonProminence) -> Color? {
        switch prominence {
        case .standard:
            return nil
        case .positive:
            return Color(nsColor: .systemGreen)
        case .caution:
            return Color(nsColor: .systemOrange)
        case .destructive:
            return Color(nsColor: .systemRed)
        }
    }

    private var streamModeGlyphSymbol: String {
        switch coordinator.streamMode {
        case .fullscreen:
            return "arrow.up.left.and.arrow.down.right"
        case .windowed:
            return "macwindow"
        }
    }

    private var streamModeHelpText: String {
        switch coordinator.streamMode {
        case .fullscreen:
            return "Switch to windowed"
        case .windowed:
            return "Switch to fullscreen"
        }
    }

    private var streamModeAccessibilityLabel: String {
        switch coordinator.streamMode {
        case .fullscreen:
            return "Fullscreen"
        case .windowed:
            return "Windowed"
        }
    }

    private enum ActionButtonProminence {
        case standard
        case positive
        case caution
        case destructive
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
