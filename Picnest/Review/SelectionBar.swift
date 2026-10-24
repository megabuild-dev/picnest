import AppKit
import PicnestCore
import SwiftUI

/// The bar at the bottom of the grid while photos are selected (spec 3.3, mockup `notsure-v3.html`):
/// the count, **Accept Best Guess**, **Move to…**, **Don't Move**, and the hints.
struct SelectionBar: View {
    let model: ReviewViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("\(model.selection.count) selected").fontWeight(.bold).monospacedDigit()
            if model.canAcceptSelection {
                Button("Accept Best Guess", systemImage: "checkmark", action: model.acceptSelection)
                    .tint(.accentColor)
                    .help("Move the selected Not sure photos to their best guess")
            }
            moveMenu
            Button("Don't Move", action: model.dontMoveSelection)
                .help("Keep the selected photos where they are")
            Button("Move to Trash", systemImage: "trash") { Task { await model.trashSelection() } }
                .help("Move the selected photos to the Trash. Undo puts them back.")
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
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 11, y: 6)
    }

    private var moveMenu: some View {
        Menu("Move to…") { MoveToMenuItems(model: model) }
            .menuStyle(.button)
            .fixedSize()
    }

    private var shortcuts: some View {
        HStack(spacing: 4) {
            KeyCap("⌘A")
            Text("select all ·")
            KeyCap("⌘Z")
            Text("undo")
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    private var hint: some View {
        HStack(spacing: 4) {
            Text("or drag to a category ·")
            KeyCap("1")
            Text("–")
            KeyCap("9")
        }
        .foregroundStyle(.secondary)
        .fixedSize()
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
            Button("\(category.emoji) \(category.displayName)\(key)") { beforeAction(); model.moveSelection(to: category.id) }
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
        Button("Quick Look") { model.contextMenuSelect(id); model.openPreview(id) }
        Button("Open") { model.contextMenuSelect(id); model.openInDefaultApp(id) }
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
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
    }
}
