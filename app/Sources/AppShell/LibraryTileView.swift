import AppKit
import MoonlightCore
import SwiftUI

struct LibraryTileView: View {
    let application: HostApplication
    let onPlay: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            poster
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0.0), radius: isHovered ? 16 : 0, y: isHovered ? 10 : 0)
            .scaleEffect(isHovered ? 1.018 : 1.0)
            .brightness(isHovered ? 0.03 : 0.0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { hovered in
                isHovered = hovered
            }
            .onTapGesture(count: 2, perform: onPlay)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .accessibilityLabel(application.name)
            .accessibilityHint("Double-click to launch or resume")
    }

    @ViewBuilder
    private var poster: some View {
        if let posterURL = application.posterURL,
           let nsImage = NSImage(contentsOf: posterURL)
        {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .clipped()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))

                Image(systemName: "play.tv")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
