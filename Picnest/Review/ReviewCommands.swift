import AppKit
import SwiftUI

extension FocusedValues {
    /// The review of the key window, for the File and Edit menus.
    @Entry var review: ReviewViewModel?
}

/// Where Edit > Undo and Redo go. In a text field (for example the Rename alert) they undo typing;
/// elsewhere they undo review changes, if the review can.
enum UndoRouting: Equatable {
    case text, review, nothing

    static func route(firstResponderIsText: Bool, reviewCanAct: Bool) -> UndoRouting {
        if firstResponderIsText { return .text }
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
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                perform(Selector(("undo:")), reviewCanAct: review?.canUndo == true) { $0.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button("Redo") {
                perform(Selector(("redo:")), reviewCanAct: review?.canRedo == true) { $0.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    @MainActor private func perform(
        _ textAction: Selector, reviewCanAct: Bool, review action: (ReviewViewModel) -> Void
    ) {
        switch UndoRouting.route(firstResponderIsText: UndoRouting.firstResponderIsText, reviewCanAct: reviewCanAct) {
        case .text: NSApp.sendAction(textAction, to: nil, from: nil)
        case .review: if let review { action(review) }
        case .nothing: break
        }
    }
}
