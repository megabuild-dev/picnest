import AppKit
import SwiftUI

extension FocusedValues {
    /// The review of the key window, for the File and Edit menus.
    @Entry var review: ReviewViewModel?
}

/// Where Edit > Undo and Redo go. In a text field (for example the Rename alert) they undo typing;
/// elsewhere they undo review changes, if the review can.
enum UndoRouting: Equatable {
    case text, editor, review, nothing

    /// The order is: a text field, then the photo editor, then the review. `editorCanAct` is nil when no editor
    /// is open. An open editor that cannot act gives `.nothing`, so a key never undoes a review change
    /// behind the editor.
    static func route(firstResponderIsText: Bool, editorCanAct: Bool? = nil, reviewCanAct: Bool) -> UndoRouting {
        if firstResponderIsText { return .text }
        if let editorCanAct { return editorCanAct ? .editor : .nothing }
        return reviewCanAct ? .review : .nothing
    }

    /// True if the key window types into a text field: its first responder is the field editor.
    @MainActor static var firstResponderIsText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }
}

/// Edit > Undo (⌘Z) and Redo (⇧⌘Z) (spec 3.3). The items stay enabled: the text field focus is not
/// observable, so the action decides with `UndoRouting` when it runs. In a text field they send the
/// standard undo: and redo: actions; elsewhere they undo or redo the review of the key window.
/// Also File > **Start Over…** (⇧⌘R) for the review of the key window.
struct ReviewCommands: Commands {
    @FocusedValue(\.review) private var review

    var body: some Commands {
        // File > Start Over… (spec 3.3). Off without a review, or while files move.
        CommandGroup(after: .newItem) {
            Button("Start Over…") { review?.requestStartOver() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(review?.canStartOver != true)
        }
        // Image > Edit Photo (⌘E): on when the photo of the anchor can open in the editor.
        CommandMenu("Image") {
            Button("Edit Photo") { review?.openEditor() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(review?.anchor.map { review?.canEdit($0) == true } != true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                perform(Selector(("undo:")), editorCanAct: review?.activeEditor?.session.canUndo, reviewCanAct: review?.canUndo == true,
                        editor: { $0.undo() }) { $0.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button("Redo") {
                perform(Selector(("redo:")), editorCanAct: review?.activeEditor?.session.canRedo, reviewCanAct: review?.canRedo == true,
                        editor: { $0.redo() }) { $0.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    @MainActor private func perform(
        _ textAction: Selector, editorCanAct: Bool?, reviewCanAct: Bool,
        editor editorAction: (any EditorSession) -> Void, review action: (ReviewViewModel) -> Void
    ) {
        switch UndoRouting.route(
            firstResponderIsText: UndoRouting.firstResponderIsText, editorCanAct: editorCanAct,
            reviewCanAct: reviewCanAct)
        {
        case .text: NSApp.sendAction(textAction, to: nil, from: nil)
        case .editor: if let session = review?.activeEditor?.session { editorAction(session) }
        case .review: if let review { action(review) }
        case .nothing: break
        }
    }
}
