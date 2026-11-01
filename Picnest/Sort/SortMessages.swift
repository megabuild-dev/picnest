import Foundation
import PicnestCore

/// The user texts for sort, undo, and save errors. The Sort sheet, the Review screen and the Welcome screen use them.
/// Each text is a literal in `String(localized:)`, so the catalog gets it.
enum SortMessages {
    /// The text when the session cannot be saved (final review I4). The Review alert and the Sort summary show it.
    static func saveFailed(_ error: any Error) -> String {
        String(localized: "Picnest could not save your changes: \(CoreErrorMessages.text(for: error))")
    }

    static func text(for error: any Error) -> String {
        guard let error = error as? SortError else { return CoreErrorMessages.text(for: error) }
        switch error {
        case .unfinishedLastSort: return String(localized: "The last sort did not finish. Click Undo Last Sort first.")
        case .changedSinceScan: return String(localized: "Some photos changed since the scan. Click Rescan, then sort again.")
        case .destinationExists: return String(localized: "Some files already exist in the destination. Choose another destination.")
        case .sizeMismatch: return String(localized: "A copy did not match its original. The original was kept.")
        case .stopped: return String(localized: "The sort stopped.")
        case .undoConflicts(let urls):
            // True for both causes: the original is missing, or a file with the same name is in its place.
            let names = urls.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
            return urls.count > 3
                ? String(localized: "Some files could not be put back. They are still in the sorted folder: \(names)…")
                : String(localized: "Some files could not be put back. They are still in the sorted folder: \(names).")
        case .nothingToUndo: return String(localized: "There is no sort to undo.")
        case .busy: return String(localized: "Another sort is still running. Try again when it stops.")
        case .movedAfterUnfinishedSort(let oldPath):
            let old = ReviewViewModel.abbreviate(oldPath, home: NSHomeDirectory())
            return String(localized: "This folder moved after a sort that did not finish. Move it back to \(old), then click Undo Last Sort.")
        }
    }
}
