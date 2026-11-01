import PicnestCore
import SwiftUI

/// The list layout of the Library (spec 4.3): 1 row per photo with a small thumbnail, the file name, the
/// category, the date and the file size. Selection, drag, Quick Look, the context menu and the keys are the same
/// as in the grid (`PhotoGridInteractions` and `photoInteractions`). The order is the sort order of the toolbar.
struct PhotoListView: View {
    let model: ReviewViewModel

    var body: some View {
        let ids = model.visibleIDs
        let selection = model.selection
        PhotoGridInteractions(model: model) { onTap in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(ids, id: \.self) { id in
                        PhotoListRow(model: model, id: id, isSelected: selection.contains(id))
                            .photoInteractions(model: model, id: id, onTap: onTap)
                            .rowFavorite(model: model, id: id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .overlay {
                if ids.isEmpty { LibraryEmptyView(model: model) }
            }
        }
    }
}

private struct PhotoListRow: View {
    static let thumbnailSize: Double = 44

    let model: ReviewViewModel
    let id: MediaID
    let isSelected: Bool

    var body: some View {
        let row = model.listRow(id)
        let shape = RoundedRectangle(cornerRadius: 6)
        HStack(spacing: 12) {
            ThumbnailImage(model: model, id: id, width: Self.thumbnailSize)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .clipShape(shape)
            Text(row.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.color)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.categoryText)
                .frame(width: 170, alignment: .leading)
            Group {
                if let date = row.date {
                    Text(date, format: .dateTime.year().month().day())
                } else {
                    Text(ReviewViewModel.noDate)
                }
            }
            .frame(width: 110, alignment: .leading)
            Text(row.fileSize, format: .byteCount(style: .file))
                .frame(width: 80, alignment: .trailing)
            // The room of the heart, which sits over it.
            if model.bodyKind != .recentlyDeleted { Color.clear.frame(width: 28, height: 1) }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.textSecondary.color)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Theme.selection.color : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.color, lineWidth: 1.5) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
        .favoriteAccessibilityAction(model: model, id: id)
    }
}
