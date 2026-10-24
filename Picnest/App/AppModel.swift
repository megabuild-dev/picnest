import Foundation
import Observation
import PicnestCore

/// Top-level state of the window: which screen shows, and the shared choices of the Welcome screen.
@MainActor
@Observable
final class AppModel {
    enum Screen {
        case welcome
        /// `rescanOf` is the session to scan again (spec 5.1), or nil for a first scan.
        case scanning(URL, rescanOf: Session? = nil)
        /// `afterScan` is true when a scan or a rescan opened the review: the Suggest Categories sheet can
        /// open by itself (spec 3.7). False for a saved session that opens again.
        case review(ReviewService, afterScan: Bool)
    }

    private(set) var screen: Screen = .welcome
    /// True while a saved session loads (embeddings from the cache, prompt vectors).
    private(set) var isOpening = false
    /// True while **Undo Last Sort** runs. There is 1 `AppModel` for the app, so every window sees it and
    /// does not start a scan, a sort, or a second undo.
    private(set) var isUndoingSort = false
    /// True while **Start Over…** runs, from the wait for the review to the first scan or an error.
    /// **Start Over…**, **Rescan**, **Sort Photos…**, and **Undo Last Sort** are off then.
    private(set) var isStartingOver = false
    /// The last error to show on the Welcome screen, or nil.
    var errorMessage: String?

    @ObservationIgnored private let library: LibraryService
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The running scans: folder path → token of `beginScan`.
    @ObservationIgnored private var activeScans: [String: UUID] = [:]

    init(environment: AppEnvironment) {
        library = environment.library
    }

    /// Remembers the folder, then opens its saved session in review, or starts a first scan.
    /// `previousPath` is the old path of a recent folder that moved: its session moves with it (spec 9).
    func open(_ url: URL, previousPath: String? = nil) {
        errorMessage = nil
        let target: OpenTarget
        do {
            target = try library.prepareOpen(url, previousPath: previousPath)
        } catch {
            show(error, opening: url)
            return
        }
        switch target {
        case .existing(let session):
            startReview(session, source: url, afterScan: false)
        case .new:
            startScan(url)
        }
    }

    /// Starts the 1 scan of `url`. Returns nil when a scan of the same folder already runs, so 2 views
    /// cannot write the same session (final review I1). Give the token to `endScan` when the scan ends.
    func beginScan(_ url: URL) -> UUID? {
        guard !isScanning(url) else { return nil }
        let token = UUID()
        activeScans[Self.scanKey(url)] = token
        return token
    }

    /// Ends the scan of `token`. Does nothing for a token that already ended.
    func endScan(_ token: UUID) {
        activeScans = activeScans.filter { $0.value != token }
    }

    /// True while a scan of `url` runs.
    func isScanning(_ url: URL) -> Bool {
        activeScans[Self.scanKey(url)] != nil
    }

    private static func scanKey(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Starts the 1 undo of the app. Returns false when an undo already runs.
    func beginUndo() -> Bool {
        guard !isUndoingSort else { return false }
        isUndoingSort = true
        return true
    }

    func endUndo() {
        isUndoingSort = false
    }

    /// Called by the Scan screen when the scan is done: updates the photo count and opens review.
    func finishScan(_ s: Session) {
        let source = URL(filePath: s.sourcePath, directoryHint: .isDirectory)
        library.remember(source, photoCount: s.scan.media.count, sortedAt: s.sortedAt)
        startReview(s, source: source, afterScan: true)
    }

    /// Scans the folder of the open review again and keeps the review work (spec 5.1).
    /// Waits until the last review change is saved, then drops the `ReviewService`, so the scan
    /// is the only writer of the session. `finishScan` opens the review again.
    func rescan() {
        guard case .review(let review, _) = screen, !isStartingOver, !isOrganizing else { return }
        let source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
        guard !isScanning(source) else { return }
        cancelPending()
        let current = generation
        pending = Task {
            await review.settled()
            // A sort or undo that still changes files must end before the scan reads the folder.
            await library.waitUntilSortIdle()
            guard current == generation, !Task.isCancelled else { return }
            screen = .scanning(source, rescanOf: review.session)
        }
    }

    /// **Start Over…** (spec 3.3): waits until the last review change is saved, deletes the session and
    /// archives the journal of the last sort, then runs a first scan of the folder. Throws, and stays on
    /// Review, if the last sort did not finish. The review saves nothing while the start over runs, and saves
    /// again if it throws. Does nothing while a start over already runs. `settled()` waits for it.
    func startOver() async throws {
        guard case .review(let review, _) = screen, !isStartingOver, !isOrganizing else { return }
        let source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
        guard !isScanning(source) else { return }
        cancelPending()
        let current = generation
        let library = self.library
        isStartingOver = true
        let run = Task {
            defer { isStartingOver = false }
            await review.settled()
            // No review save after this point can write the session file again once it is deleted.
            review.close()
            do {
                try await library.startOver(source)
            } catch {
                review.reopen()
                throw error
            }
            guard current == generation, !Task.isCancelled else { return }
            screen = .scanning(source)
        }
        pending = Task { _ = try? await run.value }
        try await run.value
    }

    /// **Done** after a sort (spec 9.1): waits until the review is saved, records the sort in the recent
    /// folder list, and closes the session. The app goes back to the Welcome screen.
    func done() {
        guard case .review(let review, _) = screen, !isOrganizing else { return }
        cancelPending()
        let current = generation
        let library = self.library
        pending = Task {
            await review.settled()
            guard current == generation, !Task.isCancelled else { return }
            library.finishSort(review.session)
            screen = .welcome
        }
    }

    // MARK: - Done (organize in place, spec 7.2)

    /// True while **Done** moves the classified photos into category folders. Every window sees it.
    private(set) var isOrganizing = false
    /// The files done and total of the running organize, or nil.
    private(set) var organizeProgress: (done: Int, total: Int)?
    /// The text of a failed organize, or nil. The Review screen shows it.
    var organizeErrorMessage: String?

    /// **Done** on the Review screen (spec 7.2): moves every classified photo into a category sub-folder
    /// of the source folder and renames it to date + category + number, then closes the session.
    /// One-way. Waits for the last review change and any sort to finish. A photo that cannot move stays
    /// where it is and is counted in the Welcome error.
    func organizeAndFinish() {
        guard case .review(let review, _) = screen, !isOrganizing else { return }
        cancelPending()
        let current = generation
        let library = self.library
        isOrganizing = true
        organizeProgress = nil
        organizeErrorMessage = nil
        pending = Task {
            await review.settled()
            await library.waitUntilSortIdle()
            guard current == generation, !Task.isCancelled else { isOrganizing = false; return }
            do {
                let result = try await library.organizeInPlace(review: review) { [weak self] done, total in
                    Task { @MainActor in self?.organizeProgress = (done, total) }
                }
                guard current == generation, !Task.isCancelled else { isOrganizing = false; return }
                isOrganizing = false
                organizeProgress = nil
                if !result.failures.isEmpty { errorMessage = Self.organizeFailureMessage(result.failures.count) }
                library.finishSort(review.session)
                screen = .welcome
            } catch {
                guard current == generation else { return }
                isOrganizing = false
                organizeProgress = nil
                organizeErrorMessage = SortMessages.text(for: error)
            }
        }
    }

    private static func organizeFailureMessage(_ count: Int) -> String {
        count == 1 ? "1 photo could not be moved. It stays where it was." :
            "\(count) photos could not be moved. They stay where they were."
    }

    /// Goes back to the Welcome screen and stops a session that is still loading.
    func showWelcome() {
        cancelPending()
        screen = .welcome
    }

    /// Waits until the latest open is done. For tests.
    func settled() async {
        while let task = pending {
            await task.value
            if pending == task { return }
        }
    }

    // MARK: - Private

    private func startReview(_ session: Session, source: URL, afterScan: Bool) {
        cancelPending()
        generation += 1
        let current = generation
        let library = self.library
        isOpening = true
        pending = Task {
            do {
                let review = try await library.openReview(session: session, source: source)
                guard current == generation, !Task.isCancelled else { return }
                screen = .review(review, afterScan: afterScan)
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                show(error, opening: source)
            }
            isOpening = false
        }
    }

    /// Shows the Scan screen for a first scan, when no sort or undo changes files.
    private func startScan(_ url: URL) {
        guard !isScanning(url) else { return }
        cancelPending()
        let current = generation
        let library = self.library
        pending = Task {
            await library.waitUntilSortIdle()
            guard current == generation, !Task.isCancelled else { return }
            screen = .scanning(url)
        }
    }

    private func cancelPending() {
        generation += 1
        pending?.cancel()
        pending = nil
        isOpening = false
    }

    private func show(_ error: any Error, opening url: URL) {
        screen = .welcome
        errorMessage = "Could not open “\(url.lastPathComponent)”. \(SortMessages.text(for: error))"
    }
}
