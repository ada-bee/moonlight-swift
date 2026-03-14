import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let libraryActionError = model.libraryActionError {
                Label(libraryActionError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

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
                    LazyVStack(spacing: 14) {
                        ForEach(model.applications) { application in
                            LibraryTileView(
                                application: application,
                                launchesFullscreen: model.launchesFullscreen(for: application.id),
                                selectedResolution: model.windowedResolution(for: application.id),
                                selectedFPS: model.windowedFPS(for: application.id),
                                playDisabled: model.launchInProgress || model.stopInProgress,
                                pauseDisabled: model.activeStreamApplicationID != application.id,
                                stopDisabled: model.stopInProgress || model.launchInProgress,
                                onPlay: {
                                    model.launch(application)
                                },
                                onPause: {
                                    model.pause(application)
                                },
                                onStop: {
                                    model.stop(application)
                                },
                                onFullscreenChange: { launchesFullscreen in
                                    model.setLaunchesFullscreen(launchesFullscreen, for: application.id)
                                },
                                onDisplayModeChange: { resolution, fps in
                                    model.setWindowedDisplayMode(resolution, fps: fps, for: application.id)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(28)
        .onAppear {
            if model.shouldRefreshLibrary && !model.libraryLoading {
                model.refreshLibrary()
            }
        }
    }
}
