import MoonlightCore
import SwiftUI

struct LibraryTileView: View {
    let application: HostApplication
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                posterSurface
                    .frame(height: 228)

                Text(application.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1.0)
    }

    @ViewBuilder
    private var posterSurface: some View {
        if let posterURL = application.posterURL,
           let nsImage = NSImage(contentsOf: posterURL)
        {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))

                Image(systemName: "play.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
