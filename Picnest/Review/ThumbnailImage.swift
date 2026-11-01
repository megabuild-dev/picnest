import PicnestCore
import SwiftUI

/// The thumbnail of 1 photo, loaded off the main thread for a view of `width` points. It shows a gray
/// placeholder until the image arrives, and a photo symbol when the image cannot load. Shared by the tile and the list row.
struct ThumbnailImage: View {
    let model: ReviewViewModel
    let id: MediaID
    let width: Double

    @State private var image: CGImage?
    @State private var failed = false

    private struct LoadKey: Hashable {
        let id: MediaID
        let maxPixel: Int
    }

    var body: some View {
        content
            .task(id: LoadKey(id: id, maxPixel: model.loadPixels(forTileWidth: width))) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            Rectangle().fill(.quaternary).overlay {
                if failed {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Waits until the width is known.
    private func load() async {
        let maxPixel = model.loadPixels(forTileWidth: width)
        guard maxPixel > 0 else { return }
        let loaded = await model.thumbnail(id, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
    }
}
