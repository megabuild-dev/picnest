import PicnestCore
import SwiftUI

/// 1 photo of the grid (spec 4.3): the rounded photo with the file name below it. Only 2 things sit on the photo:
/// the percent pill of an uncertain photo (bottom left) and the check circle of a selected photo (top right).
/// A photo with a certain score shows no percent. A photo that the user chose shows "Chosen by you" below it.
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

    /// Below this width the second line does not fit.
    private static let minWidthForSecondLine: Double = 110

    var body: some View {
        let tile = model.tile(id)
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner)
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { thumbnail }
                .overlay(alignment: .bottomLeading) { pill(tile.badge) }
                .clipShape(shape)
                .contentShape(shape)
                .overlay {
                    shape.strokeBorder(isSelected ? Theme.accent.color : Theme.textPrimary.color.opacity(0.1),
                                       lineWidth: isSelected ? 3 : 0.5)
                }
                .overlay(alignment: .topTrailing) { checkCircle }
            caption(tile)
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .task(id: LoadKey(id: id, maxPixel: model.loadPixels(forTileWidth: width))) { await load() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.accessibilityLabel)
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
        VStack(alignment: .leading, spacing: 1) {
            Text(tile.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.color)
                .lineLimit(1).truncationMode(.middle)
            if width >= Self.minWidthForSecondLine {
                if tile.badge == .you {
                    Label("Chosen by you", systemImage: "checkmark")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.confirmed.color)
                        .lineLimit(1)
                } else {
                    Text(tile.secondLine)
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary.color)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The percent pill, only for an uncertain photo.
    @ViewBuilder private func pill(_ badge: ReviewViewModel.Badge?) -> some View {
        if case .percent(let percent, true) = badge {
            Text(verbatim: "\(percent)%")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onBadge.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.badgeBackground.color.opacity(Theme.badgeAlpha), in: Capsule())
                .padding(8)
        }
    }

    /// The check circle of a selected photo: the second signal besides the ring. A thin outer ring and a shadow
    /// keep it visible on a white photo.
    @ViewBuilder private var checkCircle: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onAccent.color)
                .frame(width: 22, height: 22)
                .background(Theme.accent.color, in: Circle())
                .overlay { Circle().strokeBorder(Theme.onAccent.color, lineWidth: 1.5) }
                .shadow(color: Theme.badgeBackground.color.opacity(0.5), radius: 2)
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
