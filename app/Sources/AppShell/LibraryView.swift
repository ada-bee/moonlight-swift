import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: MainWindowModel

    private let libraryColumns = [
        GridItem(.adaptive(minimum: 138, maximum: 176), spacing: 30, alignment: .top)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if model.libraryLoading {
                    VStack(spacing: 12) {
                        ProgressView()

                        Text("Loading library...")
                            .font(.headline)

                        Text("Fetching the host app list and refreshing poster art.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let libraryError = model.libraryError {
                    ContentUnavailableView {
                        Label("Library Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(libraryError)
                    } actions: {
                        Button("Retry") {
                            model.refreshLibrary()
                        }
                        .buttonStyle(.bordered)
                    }
                } else if model.applications.isEmpty {
                    ContentUnavailableView {
                        Label("No Apps Found", systemImage: "rectangle.stack")
                    } description: {
                        Text("The host is paired, but it did not return any launchable GameStream apps.")
                    } actions: {
                        Button("Refresh") {
                            model.refreshLibrary()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if let libraryActionError = model.libraryActionError {
                                Label(libraryActionError, systemImage: "exclamationmark.triangle")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }

                            LazyVGrid(columns: libraryColumns, alignment: .leading, spacing: 30) {
                                ForEach(model.applications) { application in
                                    LibraryTileView(
                                        application: application,
                                        onPlay: {
                                            model.launch(application)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 42)
                        .padding(.top, 38)
                        .padding(.bottom, 142)
                    }
                    .scrollIndicators(.never)
                }
            }

            LibrarySessionBar(model: model)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .allowsHitTesting(model.hasRunningApplication)
        }
        .onAppear {
            if model.shouldRefreshLibrary && !model.libraryLoading {
                model.refreshLibrary()
            }
        }
    }
}

private struct LibrarySessionBar: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(model.runningApplicationTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                sessionButton(systemName: "play.fill", title: "Resume", disabled: !model.canResumeRunningApplication, action: model.resumeRunningApplication)
                sessionButton(systemName: "pause.fill", title: "Pause", disabled: !model.canPauseRunningApplication, action: model.pauseRunningApplication)
                sessionButton(systemName: "stop.fill", title: "Stop", disabled: !model.canStopRunningApplication, action: model.stopRunningApplication)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(model.hasRunningApplication ? 0.96 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(model.hasRunningApplication ? 0.14 : 0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(model.hasRunningApplication ? 0.16 : 0.08), radius: 16, y: 8)
        .opacity(model.hasRunningApplication ? 1.0 : 0.82)
    }

    private var statusColor: Color {
        if model.activeApplication != nil {
            return .green
        }

        if model.hasRunningApplication {
            return .orange
        }

        return .secondary
    }

    private func sessionButton(systemName: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(minWidth: 76)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }
}
