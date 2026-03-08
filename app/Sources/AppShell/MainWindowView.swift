import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        ZStack {
            if model.isPaired {
                LibraryView(model: model)
            } else {
                PairingView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
