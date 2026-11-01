import AppKit
import PicnestCore
import SwiftUI

/// The bar at the bottom of the grid while photos are selected (spec 3.3, mockup `notsure-v3.html`):
/// the count, **Accept Best Guess**, **Move to…**, **Don't Move**, and the hints. The Needs Review variant
/// (spec 4.3) shows thumbnails of the selection, **Move to…**, **Ignore**, and a more menu.
struct SelectionBar: View {
    enum Variant { case library, needsReview }

    let model: ReviewViewModel
    var variant: Variant = .library

    var body: some View {
        Group {
            switch variant {
            case .library: libraryContent
            case .needsReview: NeedsReviewSelectionContent(model: model)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // A system blur, not a color: it follows the wallpaper and the appearance.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.textPrimary.color.opacity(0.1), lineWidth: 0.5))
        .shadow(color: Theme.shadow.color.opacity(0.14), radius: 11, y: 6)
    }

    private var libraryContent: some View {
        HStack(spacing: 10) {
            Text("\(model.selection.count) selected").fontWeight(.bold).monospacedDigit()
            SelectionActions(model: model)
            if model.bodyKind == .recentlyDeleted {
                Spacer(minLength: 0)
            } else {
                // The hints drop out, the right one first, when the window is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        hint
                        Spacer(minLength: 10)
                        shortcuts
                    }
                    HStack(spacing: 10) {
                        hint
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .font(.system(size: 13))
        .lineLimit(1)
    }

    private var shortcuts: some View {
        HStack(spacing: 4) {
            KeyCap("⌘A")
            Text("select all ·")
            KeyCap("⌘Z")
            Text("undo")
        }
        .foregroundStyle(Theme.textSecondary.color)
        .fixedSize()
    }

    private var hint: some View {
        HStack(spacing: 4) {
            Text("or drag to a category ·")
            KeyCap("1")
            Text(verbatim: "–")
            KeyCap("9")
        }
        .foregroundStyle(Theme.textSecondary.color)
        .fixedSize()
    }
}

/// The buttons that act on the selection: **Accept Best Guess**, **Move to…**, **Don't Move**, **Move to Trash**,
/// and the more menu. In Recently Deleted only **Put Back**. The selection bar and the inspector share them.
/// The caller puts them in a stack.
struct SelectionActions: View {
    let model: ReviewViewModel

    var body: some View {
        if model.bodyKind == .recentlyDeleted {
            Button("Put Back", systemImage: "arrow.uturn.backward", action: model.putBackSelection)
                .help("Move the selected photos out of the Trash, back to their places")
        } else {
            libraryActions
        }
    }

    @ViewBuilder private var libraryActions: some View {
        if model.canAcceptSelection {
            Button("Accept Best Guess", systemImage: "checkmark", action: model.acceptSelection)
                .tint(Theme.accent.color)
                .help("Move the selected Needs Review photos to their best guess")
        }
        Menu("Move to…") { MoveToMenuItems(model: model) }
            .menuStyle(.button)
            .fixedSize()
        Button("Don't Move", action: model.dontMoveSelection)
            .help("Keep the selected photos where they are")
        Button("Move to Trash", systemImage: "trash") { Task { await model.trashSelection() } }
            .help("Move the selected photos to the Trash. Undo puts them back.")
        Menu("More", systemImage: "ellipsis") { FavoriteCollectionMenuItems(model: model, targets: Array(model.selection)) }
            .menuStyle(.button).labelStyle(.iconOnly).fixedSize()
    }
}

/// The items for favorites and collections: **Add to Favorites** or **Remove from Favorites**, **Add to Collection**,
/// and **Remove from Collection** in a collection. The selection bar and the photo context menu share them.
struct FavoriteCollectionMenuItems: View {
    let model: ReviewViewModel
    /// The photos that the items act on. They decide the text of the favorite item.
    let targets: [MediaID]
    /// Runs before each action. The context menu selects its photo here.
    var beforeAction: () -> Void = {}

    var body: some View {
        Button(FavoriteText.title(isFavorite: model.allFavorites(targets))) {
            beforeAction(); model.toggleFavoriteSelection()
        }
        Menu("Add to Collection") {
            ForEach(model.collections) { collection in
                Button(collection.name) { beforeAction(); model.addSelection(to: collection.id) }
            }
            if !model.collections.isEmpty { Divider() }
            Button("New Collection…") { beforeAction(); model.requestNewCollectionFromSelection() }
        }
        if model.canRemoveFromCollection {
            Button("Remove from Collection") { beforeAction(); model.removeSelectionFromCollection() }
        }
    }
}

/// The items of the **Move to…** menu: the categories, then **New Category…**. The selection bar and the
/// photo context menu share it.
struct MoveToMenuItems: View {
    let model: ReviewViewModel
    /// Runs before each move. The context menu selects its photo here.
    var beforeAction: () -> Void = {}

    var body: some View {
        ForEach(Array(model.categories.enumerated()), id: \.element.id) { index, category in
            // The number is text only: a real shortcut would also fire while a text field has focus.
            // The grid's key handler moves photos with keys 1 to 9.
            let key = index < 9 ? "   \(index + 1)" : ""
            Button { beforeAction(); model.moveSelection(to: category.id) } label: {
                Text(verbatim: "\(category.emoji) \(category.displayName)\(key)")
            }
        }
        Divider()
        Button("New Category…") { beforeAction(); model.requestNewCategory(movingSelection: true) }
    }
}

/// The right-click menu of a photo (spec 3.3). Each action selects the photo first (`contextMenuSelect`).
struct PhotoContextMenu: View {
    let model: ReviewViewModel
    let id: MediaID
    /// The view of the tile, so the share sheet's popover points at the photo.
    let anchor: NSView?

    var body: some View {
        // Building the menu changes nothing. Each action selects the photo first.
        if model.bodyKind == .recentlyDeleted {
            Button("Put Back") { model.contextMenuSelect(id); model.putBackSelection() }
        } else {
            libraryItems
        }
    }

    @ViewBuilder private var libraryItems: some View {
        Button("Quick Look") { model.contextMenuSelect(id); model.openPreview(id) }
        Button("Open") { model.contextMenuSelect(id); model.openInDefaultApp(id) }
        Button("Edit Photo…") { model.contextMenuSelect(id); model.openEditor(id) }
            .disabled(!model.canEdit(id))
        Button("Show in Finder") { model.contextMenuSelect(id); model.showInFinder() }
        Button("Share…") {
            model.contextMenuSelect(id)
            let urls = model.selectedURLs()
            guard !urls.isEmpty, let anchor else { return }
            let picker = NSSharingServicePicker(items: urls)
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
        Divider()
        Menu("Move to…") { MoveToMenuItems(model: model) { model.contextMenuSelect(id) } }
        if model.canAccept(model.contextTargets(for: id)) {
            Button("Accept Best Guess") { model.contextMenuSelect(id); model.acceptSelection() }
        }
        Button("Don't Move") { model.contextMenuSelect(id); model.dontMoveSelection() }
        Divider()
        FavoriteCollectionMenuItems(model: model, targets: model.contextTargets(for: id)) { model.contextMenuSelect(id) }
        Divider()
        Button("Move to Trash") { model.contextMenuSelect(id); Task { await model.trashSelection() } }
    }
}

/// A key name in a small rounded box, like the `kbd` of the mockup.
private struct KeyCap: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.placeholderFill.color, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.textPrimary.color.opacity(0.15), lineWidth: 0.5))
    }
}
