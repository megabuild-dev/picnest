import AppKit
import CoreTransferable
import PicnestCore
import SwiftUI
import UniformTypeIdentifiers

/// The photo grid (spec 3.3): `columns` flexible columns. Click, ⌘-click and ⇧-click select, ⌘A selects
/// all, Space, Return and double-click open Quick Look, keys 1 to 9 move the selection, and tiles drag to a
/// sidebar category. The selection bar shows at the bottom while photos are selected.
struct PhotoGridView: View {
    let model: ReviewViewModel

    var body: some View {
        let ids = model.visibleIDs
        let selection = model.selection
        PhotoGridInteractions(model: model) { onTap in
            ScrollView {
                LazyVGrid(columns: model.gridColumns, spacing: ReviewStyle.gridSpacing) {
                    ForEach(ids, id: \.self) { id in
                        SelectableTile(model: model, id: id, isSelected: selection.contains(id), onTap: onTap)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .overlay {
                if ids.isEmpty {
                    ContentUnavailableView("No Photos", systemImage: "photo.on.rectangle",
                                           description: Text("No photos are in this list."))
                }
            }
        }
    }
}

/// A tile with its click, double-click and drag behavior. Shared by the flat grid and the Not sure groups.
struct SelectableTile: View {
    let model: ReviewViewModel
    let id: MediaID
    let isSelected: Bool
    /// Runs after a click, so the grid takes the keyboard focus.
    let onTap: () -> Void

    var body: some View {
        PhotoTile(model: model, id: id, isSelected: isSelected)
            .onTapGesture(count: 2) { model.openPreview(id) }
            .simultaneousGesture(TapGesture().onEnded {
                model.click(id, modifiers: PhotoGridInteractions<EmptyView>.currentModifiers)
                onTap()
            })
            .draggable(MediaIDs(ids: model.dragIDs(for: id)))
            .contextMenu { PhotoContextMenu(model: model, id: id) }
    }
}

/// What every photo grid shares: the selection bar at the bottom, the focus, Space, Escape, keys 1 to 9,
/// ⌘A and Quick Look. `content` gets the function that tiles call after a click.
struct PhotoGridInteractions<Content: View>: View {
    let model: ReviewViewModel
    @ViewBuilder let content: (_ onTap: @escaping () -> Void) -> Content
    @FocusState private var isFocused: Bool

    var body: some View {
        content { isFocused = true }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !model.selection.isEmpty {
                    SelectionBar(model: model)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.space, .return]) { _ in
                guard model.anchor != nil else { return .ignored }
                model.openPreview()
                return .handled
            }
            .onKeyPress(.escape) {
                guard !model.selection.isEmpty else { return .ignored }
                model.clearSelection()
                return .handled
            }
            // ⌘⌫ moves the selection to the Trash. Only the focused grid gets it, never a text field.
            .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
                guard press.modifiers == .command, !model.selection.isEmpty else { return .ignored }
                Task { await model.trashSelection() }
                return .handled
            }
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                // Only plain digits. The grid has the focus, so typing in a text field never comes here.
                guard press.modifiers.isEmpty, let n = Int(press.characters) else { return .ignored }
                return model.moveSelection(toKey: n) ? .handled : .ignored
            }
            // ⌘A: Edit > Select All sends selectAll: to the focused view. The key press is a fallback
            // for when the menu item does not reach the grid.
            .onCommand(#selector(NSResponder.selectAll(_:))) { model.selectAll() }
            .onKeyPress(keys: ["a"], phases: .down) { press in
                guard press.modifiers == .command else { return .ignored }
                model.selectAll()
                return .handled
            }
            .photoQuickLook(model)
    }

    /// The ⌘ and ⇧ keys that are down at the click.
    static var currentModifiers: EventModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}

/// The photos of a drag from the grid to a sidebar category. The type is private to this app.
struct MediaIDs: Codable, Transferable {
    static let contentType = UTType(exportedAs: "dev.megabuild.picnest.media-ids")

    let ids: [MediaID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
