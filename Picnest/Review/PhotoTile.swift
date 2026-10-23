import PicnestCore
import SwiftUI

/// 1 photo of the grid (spec 3.3): the thumbnail, the file name and a second line on a dark gradient,
/// and the score badge at the top left.
struct PhotoTile: View {
    let model: ReviewViewModel
    let id: MediaID
    let isSelected: Bool

    @State private var width: Double = 0
    @State private var image: CGImage?
    @State private var failed = false

    private struct LoadKey: Hashable {
        let id: MediaID
        let maxPixel: Int
    }

    var body: some View {
        let tile = model.tile(id)
        let shape = RoundedRectangle(cornerRadius: ReviewStyle.tileCorner)
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { thumbnail }
            .overlay(alignment: .bottom) { caption(tile) }
            .overlay(alignment: .topLeading) { badge(tile.badge) }
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                   lineWidth: isSelected ? 3 : 0.5)
            }
            .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
            .task(id: LoadKey(id: id, maxPixel: model.loadPixels(forTileWidth: width))) { await load() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
    }

    @ViewBuilder private var thumbnail: some View {
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

    private func caption(_ tile: ReviewViewModel.TileModel) -> some View {
        let name = Text(tile.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
        let second = Text(tile.secondLine).font(.system(size: 12)).lineLimit(1)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                name
                Spacer(minLength: 0)
                second
            }
            VStack(alignment: .leading, spacing: 1) {
                name
                second.opacity(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private func badge(_ badge: ReviewViewModel.Badge?) -> some View {
        if let badge {
            let (text, color): (String, Color) = switch badge {
            case .percent(let percent, let isUncertain): ("\(percent)%", isUncertain ? ReviewStyle.amber : ReviewStyle.green)
            case .you: ("✓ You", ReviewStyle.green)
            }
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.white.opacity(0.95), in: Capsule())
                .padding(8)
        }
    }

    /// Loads the thumbnail off the main thread. Waits until the tile knows its width.
    private func load() async {
        let maxPixel = model.loadPixels(forTileWidth: width)
        guard maxPixel > 0 else { return }
        let loaded = await model.thumbnail(id, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
    }
}
