import Foundation
import Observation
import PicnestCore

/// State of the Welcome screen (spec 3.1): recent folders and folder choice.
@MainActor
@Observable
final class WelcomeViewModel {
    /// A sorted folder that the user wants to open. The view asks what to do (spec 9.1).
    struct NewSortRequest: Equatable {
        let url: URL
        let previousPath: String?
        /// True when **Undo Last Sort** shows: the journal holds paths inside the folder.
        let canUndo: Bool
        /// The dialog title: "This folder was sorted on <date>."
        let sortedText: String
    }

    static let newSortMessage = "If you start a new sort, the last sort can no longer be undone."

    /// The most recent folders, newest first. At most `BookmarkRepository.maxRecent`.
    private(set) var recent: [RecentFolder] = []
    /// The IDs of the recent folders that show **Undo Last Sort**.
    private(set) var undoableIDs: Set<String> = []
    /// The recent folder whose last sort is being undone, or nil.
    private(set) var undoingID: String?
    /// The text of the Undo Last Sort alert, or nil.
    var undoMessage: String?
    /// Set while the reopen dialog of a sorted folder shows.
    private(set) var newSortRequest: NewSortRequest?
    /// A recent folder that moved or was deleted. The view asks the user to find it (spec 9).
    private(set) var missingFolder: RecentFolder?
    /// The missing folder while the user looks for it with **Find Folder…**.
    @ObservationIgnored private var folderToFind: RecentFolder?

    var isOpening: Bool { app.isOpening }

    /// True while a folder opens or an undo runs (in any window). The drop zone, **Choose Folder…**,
    /// and the recent rows are off then.
    var isBusy: Bool { app.isOpening || app.isUndoingSort }

    var errorMessage: String? {
        get { app.errorMessage }
        set { app.errorMessage = newValue }
    }

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let library: LibraryService
    @ObservationIgnored private let dateFormatter: DateFormatter

    init(app: AppModel, library: LibraryService, locale: Locale = .current) {
        self.app = app
        self.library = library
        dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        refresh()
    }

    func refresh() {
        recent = library.recent()
        undoableIDs = Set(recent.filter(library.canUndoLastSort).map(\.id))
    }

    /// Opens a folder from **Choose Folder…** or a drop. `AppModel.open` remembers it.
    func choose(_ url: URL) {
        open(url, previousPath: nil)
    }

    /// Opens a recent folder at its current place, with its session even after a move.
    /// If it cannot be found, sets `missingFolder`.
    func openRecent(_ f: RecentFolder) {
        guard let url = library.resolve(f) else {
            missingFolder = f
            return
        }
        open(url, previousPath: f.path)
    }

    /// Closes the "Folder not found" alert and keeps the folder for `findFolder`.
    func beginFindingFolder() {
        folderToFind = missingFolder
        missingFolder = nil
    }

    /// The user found the missing folder with **Find Folder…**. Its session moves to `url`.
    func findFolder(_ url: URL) {
        open(url, previousPath: (folderToFind ?? missingFolder)?.path)
    }

    /// The user cancelled the "Folder not found" alert.
    func dismissMissingFolder() {
        missingFolder = nil
        folderToFind = nil
    }

    /// Handles dropped items. Opens the first folder and returns true. Ignores files, and any drop
    /// while a folder is opening, and returns false.
    func drop(_ urls: [URL]) -> Bool {
        guard !isBusy, let folder = urls.first(where: Self.isFolder) else { return false }
        choose(folder)
        return true
    }

    /// Opens the folder. A sorted folder shows the reopen dialog first (spec 9.1).
    /// A folder whose last sort did not finish shows the undo text at once, because a new sort would be
    /// refused (final review M7). A folder that moved after such a sort shows where to move it back (I3).
    private func open(_ url: URL, previousPath: String?) {
        missingFolder = nil
        folderToFind = nil
        guard !app.isUndoingSort else { return }
        do {
            try library.checkLastSortFinished(url, previousPath: previousPath)
        } catch SortError.unfinishedLastSort where library.isSorted(url, previousPath: previousPath) == nil {
            // Not sorted, so no question: the review opens, and its Sort sheet offers Undo Last Sort.
        } catch {
            errorMessage = SortMessages.text(for: error)
            refresh()
            return
        }
        if let sortedAt = library.isSorted(url, previousPath: previousPath) {
            newSortRequest = NewSortRequest(
                url: url, previousPath: previousPath, canUndo: library.canUndoLastSort(source: url),
                sortedText: "This folder was sorted on \(dateFormatter.string(from: sortedAt)).")
            return
        }
        app.open(url, previousPath: previousPath)
        refresh()
    }

    // MARK: - After a sort (spec 9.1)

    /// "Sorted <date>" for a sorted folder, with the medium date style. Nil when it was not sorted.
    func sortedText(_ f: RecentFolder) -> String? {
        f.sortedAt.map { "Sorted \(dateFormatter.string(from: $0))" }
    }

    /// True when the row shows **Undo Last Sort**. False for a folder that moved after the sort.
    func canUndoLastSort(_ f: RecentFolder) -> Bool {
        undoableIDs.contains(f.id)
    }

    /// **Undo Last Sort** of a recent folder. The session stays, so the folder opens in review again.
    func undoLastSort(_ f: RecentFolder) async {
        guard canUndoLastSort(f), app.beginUndo() else { return }
        undoingID = f.id
        defer {
            undoingID = nil
            app.endUndo()
            refresh()
        }
        do {
            try await library.undoLastSort(f)
        } catch {
            undoMessage = SortMessages.text(for: error)
        }
    }

    /// **Undo Last Sort** from the reopen dialog. Then the folder opens in review, with its session.
    /// If the undo fails, the message shows and the folder does not open.
    func undoFromDialog() async {
        guard let request = newSortRequest, request.canUndo, app.beginUndo() else { return }
        newSortRequest = nil
        do {
            try await library.undoLastSort(source: request.url)
        } catch {
            undoMessage = SortMessages.text(for: error)
            app.endUndo()
            refresh()
            return
        }
        app.endUndo()
        app.open(request.url, previousPath: request.previousPath)
        refresh()
    }

    /// Removes a folder from the recent list (spec 3.1). Its session stays.
    func removeRecent(_ f: RecentFolder) {
        library.removeRecent(f)
        refresh()
    }

    /// Empties the recent list (spec 3.1). Sessions stay.
    func clearRecent() {
        library.clearRecent()
        refresh()
    }

    /// The user agreed to start a new sort: the old session is deleted, and the scan starts.
    /// After an unfinished sort, nothing is deleted and the error tells the user to undo it first.
    func confirmNewSort() async {
        guard let request = newSortRequest else { return }
        newSortRequest = nil
        do {
            try await library.startNewSort(request.url, previousPath: request.previousPath)
        } catch {
            errorMessage = SortMessages.text(for: error)
            refresh()
            return
        }
        app.open(request.url, previousPath: request.previousPath)
        refresh()
    }

    /// The user cancelled the reopen dialog. Nothing changes.
    func cancelNewSort() {
        newSortRequest = nil
    }

    func photoCountText(_ f: RecentFolder) -> String {
        f.photoCount == 1 ? "1 photo" : "\(f.photoCount.formatted()) photos"
    }

    func name(_ f: RecentFolder) -> String {
        URL(filePath: f.path).lastPathComponent
    }

    /// A plain folder. Packages (for example `.app` or `.photoslibrary`) are not folders here.
    private static func isFolder(_ url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        return values.isDirectory == true && values.isPackage != true
    }
}
