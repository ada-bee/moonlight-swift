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

            menuPanel {
                headerSection
                actionSection
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            coordinator.menuBarDidOpen()
        }
        .animation(.snappy(duration: 0.18), value: coordinator.menuBarPopupPresentation.state)
        .animation(.snappy(duration: 0.18), value: coordinator.launchInProgress)
        .animation(.snappy(duration: 0.18), value: coordinator.stopInProgress)
        .animation(.snappy(duration: 0.18), value: coordinator.wakeInProgress)
    }

    private var presentation: AppCoordinator.MenuBarPopupPresentation {
        coordinator.menuBarPopupPresentation
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.status)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                Text(presentation.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            utilitySection
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            popupActionButton(presentation.primaryButton, prominence: primaryButtonProminence)
            popupActionButton(presentation.secondaryButton, prominence: .destructive, role: .destructive)
            presetSelector
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

    private var presetSelector: some View {
        Picker("Preset", selection: selectedPresetBinding) {
            ForEach(coordinator.streamPresetIDs, id: \.self) { presetID in
                Text(presetButtonTitle(for: presetID))
                    .tag(presetID)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .frame(width: 144)
        .frame(minHeight: 34)
        .help(selectedPresetHelpText)
        .disabled(coordinator.launchInProgress || coordinator.stopInProgress)
        .accessibilityLabel(selectedPresetAccessibilityLabel)
    }

    private func menuPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func popupActionButton(
        _ button: AppCoordinator.MenuBarPopupButton,
        prominence: ActionButtonProminence,
        role: ButtonRole? = nil
    ) -> some View {
        Button(role: role) {
            guard button.isEnabled else {
                return
            }

            coordinator.performMenuBarPopupAction(button.action)
            if button.action.dismissesPopup {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if button.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage = button.systemImage {
                    Image(systemName: systemImage)
                }

                Text(button.title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .font(.body.weight(.semibold))
        .layoutPriority(1)
        .tint(buttonTint(for: prominence))
        .disabled(!button.isEnabled)
        .help(button.title)
    }

    private var statusColor: Color {
        switch presentation.state {
        case .offline:
            return .secondary
        case .ready:
            return Color(nsColor: .systemGreen)
        case .paused:
            return Color(nsColor: .systemOrange)
        case .streaming:
            return Color(nsColor: .systemGreen)
        }
    }

    private var primaryButtonProminence: ActionButtonProminence {
        switch presentation.state {
        case .offline, .paused:
            return .caution
        case .ready:
            return .positive
        case .streaming:
            return .caution
        }
    }

    private var selectedPresetBinding: Binding<StreamPresetID> {
        Binding(
            get: { coordinator.selectedStreamPresetID },
            set: { coordinator.setSelectedStreamPreset($0) }
        )
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

    private func presetButtonTitle(for presetID: StreamPresetID) -> String {
        switch presetID {
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        }
    }

    private func presetButtonHelpText(for preset: AppSettings.StreamPreset) -> String {
        let mode = preset.screenMode == .fullscreen ? "Fullscreen" : "Windowed"
        let mouse = preset.mouseMode == .raw ? "Raw mouse" : "Absolute mouse"
        return "\(mode) - \(preset.resolution.width) x \(preset.resolution.height) @ \(preset.fps) Hz - \(mouse)"
    }

    private var selectedPresetHelpText: String {
        let presetID = coordinator.selectedStreamPresetID
        let preset = coordinator.streamPreset(for: presetID)
        return "Preset \(presetButtonTitle(for: presetID)): \(presetButtonHelpText(for: preset))"
    }

    private var selectedPresetAccessibilityLabel: String {
        let presetID = coordinator.selectedStreamPresetID
        let preset = coordinator.streamPreset(for: presetID)
        return "Preset selector, selected preset \(presetButtonTitle(for: presetID)), \(presetButtonHelpText(for: preset))"
    }

    private enum ActionButtonProminence {
        case standard
        case positive
        case caution
        case destructive
    }
}

struct MenuBarStatusIcon: View {
    var body: some View {
        Image(nsImage: MenuBarIconAsset.image)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
        .frame(width: 20, height: 18)
    }
}
