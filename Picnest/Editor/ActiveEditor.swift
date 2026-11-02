import Foundation

/// What every editor of the window offers to the host: the undo history and the close request. The host
/// (`ReviewViewModel`, `ReviewCommands`, `ReviewView`) uses only this, so the editors share 1 place for the
/// sidebar, the toolbar, and the undo keys.
@MainActor
protocol EditorSession: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func undo()
    func redo()
    /// True from the click on **Export** until the write ends, with the save panel open too. The editor refuses
    /// to close then, so the lock on **Done** and **Rescan** stays on and no error is lost.
    var isExporting: Bool { get }
    /// True if the editor holds an edit that no export wrote. The quit asks first (final review I1).
    var hasUnexportedEdits: Bool { get }
    /// Saves what the editor keeps only in memory, before the app quits. The layout editor saves its draft.
    func flushForQuit()
    /// Asks the editor to close. The editor may ask first, then calls its `onClose`.
    func requestClose()
}

/// The editor that fills the window, or none.
enum ActiveEditor {
    case photo(PhotoEditorViewModel)
    case layout(LayoutEditorViewModel)

    /// False for the layout editor: it has Redo in its own header.
    var hasToolbarRedo: Bool {
        if case .photo = self { true } else { false }
    }

    var session: any EditorSession {
        switch self {
        case .photo(let editor): editor
        case .layout(let editor): editor
        }
    }
}
