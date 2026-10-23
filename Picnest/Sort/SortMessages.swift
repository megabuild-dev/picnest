import Foundation
import PicnestCore

/// The user texts for sort, undo, and save errors. The Sort sheet, the Review screen and the Welcome screen use them.
enum SortMessages {
    /// The text when the session cannot be saved (final review I4). The Review alert and the Sort summary show it.
    static func saveFailed(_ error: any Error) -> String {
        "Picnest could not save your changes: \(error.localizedDescription)"
    }

    static func text(for error: any Error) -> String {
        guard let error = error as? SortError else { return error.localizedDescription }
        switch error {
        case .unfinishedLastSort: return "The last sort did not finish. Click Undo Last Sort first."
        case .changedSinceScan: return "Some photos changed since the scan. Click Rescan, then sort again."
        case .destinationExists: return "Some files already exist in the destination. Choose another destination."
        case .sizeMismatch: return "A copy did not match its original. The original was kept."
        case .stopped: return "The sort stopped."
        case .undoConflicts(let urls):
            // True for both causes: the original is missing, or a file with the same name is in its place.
            let names = urls.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
            return "Some files could not be put back. They are still in the sorted folder: \(names)"
                + (urls.count > 3 ? "…" : ".")
        case .nothingToUndo: return "There is no sort to undo."
        case .busy: return "Another sort is still running. Try again when it stops."
        case .movedAfterUnfinishedSort(let oldPath):
            let old = ReviewViewModel.abbreviate(oldPath, home: NSHomeDirectory())
            return "This folder moved after a sort that did not finish. Move it back to \(old), then click Undo Last Sort."
        }
    }
}
