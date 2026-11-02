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
    /// Asks the editor to close. The editor may ask first, then calls its `onClose`.
    func requestClose()
}

/// The editor that fills the window, or none.
enum ActiveEditor {
    case photo(PhotoEditorViewModel)
    case layout(LayoutEditorViewModel)

    var session: any EditorSession {
        switch self {
        case .photo(let editor): editor
        case .layout(let editor): editor
        }
    }
}
