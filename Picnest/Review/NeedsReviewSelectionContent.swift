import PicnestCore
import SwiftUI

/// The inside of the selection bar in Needs Review: up to 3 thumbnails, the count and a hint, then
/// **Move to…**, **Ignore** and a more menu. **Ignore** keeps the photos where they are.
struct NeedsReviewSelectionContent: View {
    let model: ReviewViewModel

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(model.selectionPreviewIDs, id: \.self) { id in
                    ThumbnailImage(model: model, id: id, width: 44)
                        .frame(width: 44, height: 33)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent.color, lineWidth: 1.5))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.selection.count) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.color)
                Text("Choose a category, move, or ignore.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary.color)
            }
            .lineLimit(1)
            Spacer(minLength: 10)
            Menu { MoveToMenuItems(model: model) } label: {
                Label("Move to…", systemImage: "folder")
            }
            .menuStyle(.button)
            .fixedSize()
            Button("Ignore", systemImage: "eye.slash", action: model.dontMoveSelection)
                .help("Keep the selected photos where they are")
            Menu {
                if model.canAcceptSelection {
                    Button("Accept Best Guess", systemImage: "checkmark", action: model.acceptSelection)
                }
                Button("Move to Trash", systemImage: "trash") { Task { await model.trashSelection() } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .font(.system(size: 13))
    }
}
