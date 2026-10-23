import Foundation
import os

/// What `LibraryService.prepareOpen` found for a folder.
public enum OpenTarget: Sendable {
    /// A saved session. Open it in review.
    case existing(Session)
    /// No session. Start a first scan.
    case new
}

/// Recent folders, opening a folder, and the folder after a sort (spec 3.1, 9, 9.1). The view models use
/// this service, not the session and bookmark repositories.
public final class LibraryService: Sendable {
    private static let log = Logger(subsystem: SessionRepository.bundleID, category: "LibraryService")

    private let sessions: SessionRepository
    private let bookmarks: BookmarkRepository
    private let scanService: ScanService
    private let classify: ClassifyService
    private let sortService: SortService
    private let trashService: TrashService
    private let images: ImageRepository

    /// `sortService` is the 1 sort service of the app (its busy guard is per instance). `trashService` is
    /// the 1 Trash service that every review of this library uses. `images` is the image repository of the
    /// app (the one of `ThumbnailService`); reviews read pixel sizes through it.
    public init(sessions: SessionRepository, bookmarks: BookmarkRepository, scanService: ScanService,
                classify: ClassifyService, sortService: SortService, trashService: TrashService = TrashService(),
                images: ImageRepository = ImageRepository()) {
        self.sessions = sessions
        self.bookmarks = bookmarks
        self.scanService = scanService
        self.classify = classify
        self.sortService = sortService
        self.trashService = trashService
        self.images = images
    }

    /// The most recent folders, newest first. At most `BookmarkRepository.maxRecent`.
    public func recent() -> [RecentFolder] {
        Array(bookmarks.recent().prefix(BookmarkRepository.maxRecent))
    }

    /// The current URL of a recent folder, even after a move. Nil when it cannot be found.
    public func resolve(_ f: RecentFolder) -> URL? {
        bookmarks.resolve(f)
    }

    /// Loads the session of `url`. When it has none and `previousPath` (the old path of a moved or
    /// renamed folder) has one, moves that session to `url` (spec 9). Then remembers the folder in
    /// the recent list, in place of the `previousPath` entry. Throws when a session file is corrupt.
    ///
    /// A moved session that was sorted keeps `sortedAt`, but its journal is archived: the journal holds
    /// the old absolute paths, so **Undo Last Sort** cannot run for it.
    ///
    /// Throws `SortError.movedAfterUnfinishedSort`, and changes nothing, when the journal of `previousPath`
    /// has no `done` line: the user must move the folder back and undo that sort first (final review I3).
    public func prepareOpen(_ url: URL, previousPath: String? = nil) throws -> OpenTarget {
        var session = try sessions.load(source: url)
        if session == nil, let previousPath, previousPath != url.canonicalKeyPath {
            let old = URL(filePath: previousPath, directoryHint: .isDirectory)
            if sortService.hasUnfinishedSort(journal: journal(for: old)) {
                throw SortError.movedAfterUnfinishedSort(oldPath: previousPath)
            }
            session = try sessions.relink(from: old, to: url)
            if session?.sortedAt != nil { try journal(for: url).archive(suffix: "relinked") }
        }
        if let previousPath, previousPath != url.canonicalKeyPath {
            do {
                try bookmarks.forget(id: previousPath)
            } catch {
                Self.log.error("Could not forget recent folder: \(error.localizedDescription, privacy: .public)")
            }
        }
        remember(url, photoCount: session?.scan.media.count ?? 0, sortedAt: session?.sortedAt)
        return session.map(OpenTarget.existing) ?? .new
    }

    /// Removes 1 folder from the recent list (spec 3.1). Its session, journal, and files stay.
    public func removeRecent(_ f: RecentFolder) {
        do {
            try bookmarks.forget(id: f.id)
        } catch {
            Self.log.error("Could not remove recent folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Empties the recent list (spec 3.1). Sessions stay.
    public func clearRecent() {
        do {
            try bookmarks.clear()
        } catch {
            Self.log.error("Could not clear recent folders: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds the folder to the top of the recent list. A failure is logged, not thrown:
    /// the folder can still open.
    public func remember(_ url: URL, photoCount: Int, sortedAt: Date?) {
        do {
            try bookmarks.remember(url, photoCount: photoCount, sortedAt: sortedAt)
        } catch {
            Self.log.error("Could not remember recent folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The journal of the last sort of `source`. It lives in the session folder (spec 9).
    public func journal(for source: URL) -> JournalRepository {
        JournalRepository(directory: sessions.directory(for: source))
    }

    // MARK: - After a sort (spec 9.1)

    /// **Done** after a sort: the recent folder list shows "Sorted <date>" for the folder.
    public func finishSort(_ session: Session) {
        remember(URL(filePath: session.sourcePath, directoryHint: .isDirectory),
                 photoCount: session.scan.media.count, sortedAt: session.sortedAt)
    }

    /// The time of the last sort of the session of `url`, or of `previousPath` when `url` has no session.
    /// Nil when the folder was not sorted, has no session, or its session file cannot be read.
    public func isSorted(_ url: URL, previousPath: String? = nil) -> Date? {
        if let session = try? sessions.load(source: url) { return session.sortedAt }
        guard let previousPath,
              let session = try? sessions.load(source: URL(filePath: previousPath, directoryHint: .isDirectory))
        else { return nil }
        return session.sortedAt
    }

    /// The user agreed to start a new sort: deletes the old session of `url` (and of `previousPath`),
    /// with its journal and embedding cache. The last sort can no longer be undone.
    /// Waits until no sort or undo runs. Throws the error of `checkLastSortFinished`, and deletes nothing,
    /// when a journal has no `done` line: the user must click **Undo Last Sort** first (spec 7.3, rule 6).
    public func startNewSort(_ url: URL, previousPath: String? = nil) async throws {
        await sortService.waitUntilIdle()
        try checkLastSortFinished(url, previousPath: previousPath)
        var sources = [url]
        if let previousPath, previousPath != url.canonicalKeyPath {
            sources.append(URL(filePath: previousPath, directoryHint: .isDirectory))
        }
        for source in sources { try sessions.delete(source: source) }
        remember(url, photoCount: 0, sortedAt: nil)
    }

    /// **Start Over…** (spec 3.3): forgets the categories and review work of `url`, so the next open runs a
    /// first scan. Deletes only the session file: the embedding cache, `hashes.json`, and the photos stay.
    /// A journal is archived as `<timestamp>.startover`, so **Undo Last Sort** no longer shows for the folder.
    /// Waits until no sort or undo runs. Throws `SortError.unfinishedLastSort`, and deletes nothing, when
    /// the journal has no `done` line.
    public func startOver(_ url: URL) async throws {
        await sortService.waitUntilIdle()
        try checkLastSortFinished(url)
        let photoCount = (try? sessions.load(source: url))?.scan.media.count ?? 0
        let journal = journal(for: url)
        if journal.exists { try journal.archive(suffix: SortService.timestamp() + ".startover") }
        try sessions.deleteSessionFile(source: url)
        remember(url, photoCount: photoCount, sortedAt: nil)
    }

    /// Throws when the last sort of `url` did not finish: `SortError.unfinishedLastSort` for the journal
    /// of `url`, or `SortError.movedAfterUnfinishedSort` for the journal of `previousPath` (the old path of a
    /// moved folder). The Welcome screen asks this before "Start a new sort?" (spec 7.3, rule 6).
    public func checkLastSortFinished(_ url: URL, previousPath: String? = nil) throws {
        if sortService.hasUnfinishedSort(journal: journal(for: url)) { throw SortError.unfinishedLastSort }
        if let previousPath, previousPath != url.canonicalKeyPath,
           sortService.hasUnfinishedSort(journal: journal(for: URL(filePath: previousPath, directoryHint: .isDirectory))) {
            throw SortError.movedAfterUnfinishedSort(oldPath: previousPath)
        }
    }

    /// True while a sort or an undo changes files. The app does not quit then (final review M4).
    public var isSortRunning: Bool {
        sortService.isRunning
    }

    /// Returns when no sort or undo runs. Call it before a scan starts, so the scan is the only writer.
    public func waitUntilSortIdle() async {
        await sortService.waitUntilIdle()
    }

    /// True when the recent folder shows **Undo Last Sort**: it was sorted, it is still at the path of
    /// the sort (the journal holds absolute paths), and its journal exists.
    public func canUndoLastSort(_ f: RecentFolder) -> Bool {
        guard f.sortedAt != nil, let url = resolve(f), url.canonicalKeyPath == f.path else { return false }
        return journal(for: url).exists
    }

    /// True when `source` has a journal and every source path in it is inside `source`. A moved folder
    /// has no journal, or one with the old paths, so this is false for it.
    public func canUndoLastSort(source: URL) -> Bool {
        let journal = journal(for: source)
        guard journal.exists, let entries = try? journal.read() else { return false }
        // The journal may hold the path as given or the canonical one (symlinks resolved).
        let prefixes = Set([source.path(percentEncoded: false), source.canonicalKeyPath]).map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return entries.allSatisfy { entry in
            guard let path = entry.source else { return true }
            return prefixes.contains { path.hasPrefix($0) }
        }
    }

    /// **Undo Last Sort** from the recent folder list. Reverses the journal, then clears `sortedAt` in
    /// the session and the recent list. The session stays, so the folder opens in review again.
    /// Does nothing when `canUndoLastSort(f)` is false. With no journal, only clears `sortedAt`.
    /// Throws `SortError.undoConflicts` after the journal is archived, and other errors as they come.
    public func undoLastSort(_ f: RecentFolder) async throws {
        guard f.sortedAt != nil, let url = resolve(f), url.canonicalKeyPath == f.path else { return }
        try await undoLastSort(of: url, photoCount: f.photoCount)
    }

    /// **Undo Last Sort** of a folder that may not be in the recent list (the reopen dialog). Same rules as
    /// `undoLastSort(_:)`. The folder goes to the top of the recent list with `sortedAt` cleared.
    public func undoLastSort(source: URL) async throws {
        try await undoLastSort(of: source, photoCount: 0)
    }

    private func undoLastSort(of url: URL, photoCount: Int) async throws {
        let (cleared, error) = await reverseLastSort(of: url)
        if cleared {
            var photoCount = photoCount
            do {
                if var session = try sessions.load(source: url) {
                    session.sortedAt = nil
                    try sessions.save(session)
                    photoCount = session.scan.media.count
                }
            } catch {
                Self.log.error("Could not clear the sort time: \(error.localizedDescription, privacy: .public)")
            }
            remember(url, photoCount: photoCount, sortedAt: nil)
        }
        if let error { throw error }
    }

    /// **Undo Last Sort** in the open review. Works as `undoLastSort(_:)`, but `review` clears `sortedAt`,
    /// because it is the writer of its session.
    @MainActor
    public func undoLastSort(review: ReviewService) async throws {
        await review.settled()
        let source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
        let (cleared, error) = await reverseLastSort(of: source)
        if cleared {
            review.clearSorted()
            remember(source, photoCount: review.session.scan.media.count, sortedAt: nil)
        }
        if let error { throw error }
    }

    /// Runs `SortService.undo` off the main actor. Waits first when another sort or undo is finishing,
    /// and tries 1 more time after a `.busy`. `cleared` is true when no last sort is left to undo:
    /// the undo ran, no journal exists, or the journal was archived with conflicts.
    private func reverseLastSort(of source: URL) async -> (cleared: Bool, error: (any Error)?) {
        let service = sortService, journal = journal(for: source)
        var result: Result<Void, any Error> = .failure(SortError.busy)
        for _ in 0..<2 {
            await service.waitUntilIdle()
            result = await Task.detached(priority: .userInitiated) { Result { try service.undo(journal: journal) } }.value
            guard case .failure(SortError.busy) = result else { break }
        }
        switch result {
        case .success, .failure(SortError.nothingToUndo):
            return (true, nil)
        case .failure(let error):
            if case SortError.undoConflicts = error {
                // Undo archives the journal before it reports conflicts. Clear only if that happened.
                let archived = !journal.exists
                return (archived, error)
            }
            return (false, error)
        }
    }

    /// Makes the review service of a session. Loading the model and the embeddings runs off the main actor.
    @MainActor
    public func openReview(session: Session, source: URL) async throws -> ReviewService {
        let scanService = self.scanService
        let embeddings = try await Task.detached { try scanService.embeddingRepository(for: source) }.value
        return try await ReviewService.open(
            session: session, source: source, embeddings: embeddings, classify: classify, sessions: sessions,
            trash: trashService, hashes: HashRepository(cacheDirectory: sessions.directory(for: source)),
            imageFiles: images)
    }
}
