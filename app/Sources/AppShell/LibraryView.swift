import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: MainWindowModel

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 16, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Library")
                .font(.largeTitle)
                .foregroundStyle(.primary)

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
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(model.applications) { application in
                            LibraryTileView(application: application, isDisabled: model.launchInProgress) {
                                model.launch(application)
                            }
                        }
                    }
                    .padding(.bottom, 8)
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
