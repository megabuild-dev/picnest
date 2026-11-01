import PicnestCore
import SwiftUI

/// 1 group: a rounded card with the photos side by side, then **Not duplicates** and **Clean Up (N)** with
/// the line that says how many photos go to the Trash.
struct DuplicateGroupCard: View {
    let model: DuplicatesViewModel
    let group: DuplicateGroup
    /// Runs after a click, so the view takes the keyboard focus (Space and Return).
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(group.ids, id: \.self) { id in
                        DuplicateTile(
                            model: model, id: id, isKeep: model.isKeep(id, in: group),
                            onChoose: {
                                model.toggleKeep(id, in: group)
                                onTap()
                            },
                            onOpen: { model.openPreview(id) })
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.automatic)
            HStack {
                Label(model.trashSummary(of: group), systemImage: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary.color)
                Spacer()
                Button("Not duplicates") { model.notDuplicates(group) }
                Button(model.trashTitle(of: group)) { Task { await model.trash(group) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.trashCount(of: group) == 0 || model.isCleaning)
                    .accessibilityLabel(model.trashTitle(of: group))
                    .accessibilityHint(model.trashSummary(of: group))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.textSecondary.color.opacity(0.18)))
    }
}

/// 1 photo of a card: the thumbnail with a **Kept** or **Trash** badge, the file name, the pixel size, the
/// file size, and a radio-like **Keep** choice (a check icon and a ring, not only a color).
private struct DuplicateTile: View {
    let model: DuplicatesViewModel
    let id: MediaID
    let isKeep: Bool
    /// One click on the photo or the **Keep** choice: toggles Keep once.
    let onChoose: () -> Void
    /// A double-click on the photo.
    let onOpen: () -> Void

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        let tile = model.tile(id)
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner)
        VStack(alignment: .leading, spacing: 5) {
            // The click area is the photo and its text. The Keep button below is outside it, so 1 click on
            // the button toggles Keep once and never reaches the tap gestures of the photo.
            VStack(alignment: .leading, spacing: 5) {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { thumbnail }
                    .overlay(alignment: .topLeading) { stateBadge }
                    .clipShape(shape)
                    .contentShape(shape)
                    .overlay {
                        shape.strokeBorder(isKeep ? Theme.confirmed.color : Theme.textSecondary.color.opacity(0.25),
                                           lineWidth: isKeep ? 2.5 : 0.5)
                    }
                    .opacity(isKeep ? 1 : 0.8)
                Text(tile.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details(tile))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary.color)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            // Double-click first, so a double-click never changes Keep.
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(perform: onChoose)
            keepChoice
        }
        .frame(width: DuplicatesViewModel.tileWidth)
        .task(id: id) { await load() }
        .help(isKeep ? LocalizedStringKey("Keep. Click to unmark.") : LocalizedStringKey("Click to mark Keep."))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(tile))
        .accessibilityAddTraits(isKeep ? [.isImage, .isSelected] : .isImage)
        .accessibilityAction(named: Text("Keep"), onChoose)
    }

    private func details(_ tile: DuplicatesViewModel.TileModel) -> String {
        let pixels = tile.pixelSize.isEmpty ? "—" : tile.pixelSize
        let bytes = tile.fileSize.isEmpty ? "—" : tile.fileSize
        return "\(pixels) · \(bytes)"
    }

    private func accessibilityText(_ tile: DuplicatesViewModel.TileModel) -> String {
        let state = isKeep ? String(localized: "Kept") : String(localized: "Trash")
        return [tile.name, tile.pixelSize, tile.fileSize, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            Rectangle().fill(Theme.background.color).overlay {
                if failed {
                    Image(systemName: "photo").font(.title2).foregroundStyle(Theme.textSecondary.color)
                }
            }
        }
    }

    /// **Kept** (filled `confirmed`) or **Trash** (dark pill), always with an icon and text.
    @ViewBuilder private var stateBadge: some View {
        if isKeep {
            Label("Kept", systemImage: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onConfirmed.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.confirmed.color, in: Capsule())
                .padding(8)
        } else {
            Label("Trash", systemImage: "trash")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onBadge.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.badgeBackground.color.opacity(Theme.badgeAlpha), in: Capsule())
                .padding(8)
        }
    }

    private var keepChoice: some View {
        Button(action: onChoose) {
            Label("Keep", systemImage: isKeep ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isKeep ? Theme.confirmed.color : Theme.textSecondary.color)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func load() async {
        let loaded = await model.thumbnail(id, maxPixel: DuplicatesViewModel.tileMaxPixel)
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
    }
}
