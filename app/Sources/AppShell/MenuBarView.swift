import AppKit
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
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionSection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            coordinator.menuBarDidOpen()
        }
    }

    private var sessionSection: some View {
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

    private var runningSessionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionStatusText)
                        .font(.headline)
                        .foregroundStyle(sessionStatusColor)
                        .lineLimit(1)

                    Text(streamInfoText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

            Toggle("Fullscreen", isOn: fullscreenBinding)
                .toggleStyle(.switch)
                .disabled(coordinator.launchInProgress || coordinator.stopInProgress)

            Text(fullscreenHelpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inactiveSessionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hostStatusText)
                    .font(.headline)
                    .foregroundStyle(hostStatusColor)

                Text(hostDetailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch coordinator.hostAvailabilityState {
            case .unreachable:
                if coordinator.hasWakeOnLANConfiguration {
                    Button("Send Wake Packet", action: coordinator.sendWakeOnLANMagicPacket)
                        .buttonStyle(.borderedProminent)
                }

            case .unconfigured, .checking, .reachable:
                EmptyView()
            }

            if canRunPrimaryAction {
                Button(primaryActionTitle, action: handlePrimaryAction)
                    .buttonStyle(.bordered)
            }
        }
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

    private var fullscreenHelpText: String {
        if coordinator.streamMode == .fullscreen {
            return "Fullscreen uses raw mouse input and reconnects at the display's native size and refresh rate."
        }

        return "Windowed uses absolute cursor input and the resolution and frame rate from Settings."
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
