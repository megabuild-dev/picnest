import PicnestCore
import SwiftUI

/// The text of the favorite actions. The heart, the inspector, the menus and the accessibility action share it.
enum FavoriteText {
    static func title(isFavorite: Bool) -> LocalizedStringKey {
        isFavorite ? "Remove from Favorites" : "Add to Favorites"
    }
}

/// The heart of 1 photo. A click toggles that photo only and keeps the selection. The tile and the list row
/// show it on hover, and always for a favorite. The inspector shows it always.
struct FavoriteButton: View {
    let model: ReviewViewModel
    let id: MediaID
    /// True on the photo of the grid: a shadow keeps the heart visible on a white photo.
    var onPhoto = false

    var body: some View {
        let isFavorite = model.isFavorite(id)
        Button { model.toggleFavorite(id) } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.accent.color : (onPhoto ? Theme.onAccent.color : Theme.textSecondary.color))
                .shadow(color: onPhoto ? Theme.badgeBackground.color.opacity(0.6) : .clear, radius: 2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(FavoriteText.title(isFavorite: isFavorite))
        .accessibilityLabel(FavoriteText.title(isFavorite: isFavorite))
    }
}

/// Puts the heart over a tile or a row, outside the view with the click and drag gestures, so a click on the
/// heart never selects the photo. Not in Recently Deleted.
private struct FavoriteOverlay: ViewModifier {
    enum Placement { case tile, row }

    let model: ReviewViewModel
    let id: MediaID
    let placement: Placement

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay {
                if model.bodyKind != .recentlyDeleted, hovering || model.isFavorite(id) {
                    switch placement {
                    case .tile:
                        // The heart sits at the bottom right of the 4:3 photo, not of the caption below it.
                        VStack(spacing: 0) {
                            Color.clear
                                .aspectRatio(4 / 3, contentMode: .fit)
                                .overlay(alignment: .bottomTrailing) {
                                    FavoriteButton(model: model, id: id, onPhoto: true).padding(4)
                                }
                            Spacer(minLength: 0)
                        }
                    case .row:
                        HStack {
                            Spacer(minLength: 0)
                            FavoriteButton(model: model, id: id).padding(.trailing, 6)
                        }
                    }
                }
            }
    }
}

extension View {
    /// The hover heart of a grid tile.
    func tileFavorite(model: ReviewViewModel, id: MediaID) -> some View {
        modifier(FavoriteOverlay(model: model, id: id, placement: .tile))
    }

    /// The hover heart of a list row.
    func rowFavorite(model: ReviewViewModel, id: MediaID) -> some View {
        modifier(FavoriteOverlay(model: model, id: id, placement: .row))
    }
}
