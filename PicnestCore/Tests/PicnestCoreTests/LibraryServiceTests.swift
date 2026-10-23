import Foundation
import Testing
@testable import PicnestCore

@MainActor
final class LibraryServiceTests {
    private let dir: TempDir
    private let suiteName = "test-\(UUID())"
    private let defaults: UserDefaults
    private let sessions: SessionRepository
    private let bookmarks: BookmarkRepository
    private let library: LibraryService
    private let sortService = SortService()

    init() throws {
        dir = try TempDir()
        defaults = UserDefaults(suiteName: suiteName)!
        sessions = SessionRepository(root: dir.url.appending(path: "Sessions", directoryHint: .isDirectory))
        bookmarks = BookmarkRepository(defaults: defaults)
        let embedder = FakeEmbedder(dimension: 2, images: ["p.jpg": [1, 0]], texts: ["food": [1, 0]])
        let scan = ScanService(makeEmbedder: { embedder }, sessions: sessions)
        library = LibraryService(sessions: sessions, bookmarks: bookmarks, scanService: scan, classify: ClassifyService(),
                                 sortService: sortService)
    }

    deinit { UserDefaults().removePersistentDomain(forName: suiteName) }

    private func folder(_ name: String) throws -> URL {
        let url = dir.url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func saveSession(for source: URL, sortedAt: Date? = nil) throws -> Session {
        let category = Category(id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 0)
        let file = MediaFile(id: "p.jpg", relativePath: "p.jpg", kind: .image, size: 10,
                             modified: Date(timeIntervalSince1970: 1000))
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [category],
            states: ["p.jpg": .manual(category.id)], scan: ScanResult(media: [file], dates: [:], skipped: [:]),
            sortedAt: sortedAt)
        try sessions.save(session)
        return session
    }

    @Test func newFolderIsNewAndRemembered() throws {
        let a = try folder("A")
        guard case .new = try library.prepareOpen(a) else { Issue.record("expected .new"); return }
        #expect(library.recent().map(\.id) == [a.canonicalKeyPath])
        #expect(library.recent().first?.photoCount == 0)
    }

    @Test func savedSessionIsExistingWithCount() throws {
        let a = try folder("A")
        let sorted = Date(timeIntervalSince1970: 1_700_000_000)
        try saveSession(for: a, sortedAt: sorted)
        guard case .existing(let s) = try library.prepareOpen(a) else { Issue.record("expected .existing"); return }
        #expect(s.scan.media.count == 1)
        #expect(library.recent().first?.photoCount == 1)
        #expect(library.recent().first?.sortedAt == sorted)
    }

    @Test func movedFolderRelinksSession() throws {
        let old = try folder("Old")
        try saveSession(for: old)
        library.remember(old, photoCount: 1, sortedAt: nil)
        let oldPath = old.canonicalKeyPath
        let oldDirectory = sessions.directory(for: old)
        let new = dir.url.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: new)

        guard case .existing(let s) = try library.prepareOpen(new, previousPath: oldPath) else {
            Issue.record("expected .existing"); return
        }
        #expect(s.sourcePath == new.canonicalKeyPath)
        #expect(try sessions.load(source: new)?.sourcePath == new.canonicalKeyPath)
        #expect(!FileManager.default.fileExists(atPath: oldDirectory.path))
        #expect(library.recent().map(\.path) == [new.canonicalKeyPath])
    }

    @Test func relinkReplacesPartialDataAtNewPath() throws {
        let old = try folder("Old")
        try saveSession(for: old)
        let new = try folder("New")
        let stale = sessions.directory(for: new)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([1]).write(to: stale.appending(path: "embeddings.f32"))

        guard case .existing = try library.prepareOpen(new, previousPath: old.canonicalKeyPath) else {
            Issue.record("expected .existing"); return
        }
        #expect(!FileManager.default.fileExists(atPath: stale.appending(path: "embeddings.f32").path))
    }

    @Test func previousPathWithoutSessionIsNewAndReplacesEntry() throws {
        let old = try folder("Old")
        library.remember(old, photoCount: 0, sortedAt: nil)
        let new = try folder("New")
        guard case .new = try library.prepareOpen(new, previousPath: old.canonicalKeyPath) else {
            Issue.record("expected .new"); return
        }
        #expect(library.recent().map(\.path) == [new.canonicalKeyPath])
    }

    @Test func existingSessionAtNewPathWins() throws {
        let old = try folder("Old"), new = try folder("New")
        try saveSession(for: old)
        try saveSession(for: new)
        guard case .existing(let s) = try library.prepareOpen(new, previousPath: old.canonicalKeyPath) else {
            Issue.record("expected .existing"); return
        }
        #expect(s.sourcePath == new.path(percentEncoded: false))
        #expect(try sessions.load(source: old) != nil)
    }

    @Test func recentShowsAtMostFive() throws {
        for i in 0..<7 { library.remember(try folder("F\(i)"), photoCount: i, sortedAt: nil) }
        #expect(library.recent().count == 5)
    }

    @Test func resolveMissingFolderIsNil() throws {
        let a = try folder("A")
        library.remember(a, photoCount: 0, sortedAt: nil)
        let entry = try #require(library.recent().first)
        #expect(library.resolve(entry)?.canonicalKeyPath == a.canonicalKeyPath)
        try FileManager.default.removeItem(at: a)
        #expect(library.resolve(entry) == nil)
    }

    @Test func journalLivesInSessionFolder() throws {
        let a = try folder("A")
        #expect(library.journal(for: a).directory == sessions.directory(for: a))
    }

    // MARK: - After a sort (spec 9.1)

    /// A sorted folder: `source/p.jpg`, its copy in `dest/Food/p.jpg`, a complete journal, and a session
    /// with `sortedAt`. The folder is in the recent list with `sortedAt`.
    private func sortedFolder(_ name: String = "A", at date: Date = Date(timeIntervalSince1970: 1_700_000_000))
        throws -> (source: URL, copy: URL)
    {
        let source = try folder(name)
        try Data([1, 2, 3]).write(to: source.appending(path: "p.jpg"))
        let made = try folder(name + " - sorted/Food")
        let copy = made.appending(path: "p.jpg")
        try Data([1, 2, 3]).write(to: copy)
        let journal = library.journal(for: source)
        try journal.append(JournalEntry(op: .mkdir, source: nil, destination: made.path, time: date))
        try journal.append(JournalEntry(op: .copy, source: source.appending(path: "p.jpg").path,
                                        destination: copy.path, time: date))
        try journal.append(JournalEntry(op: .done, source: nil, destination: nil, time: date))
        try saveSession(for: source, sortedAt: date)
        library.remember(source, photoCount: 1, sortedAt: date)
        return (source, copy)
    }

    private func entry(_ url: URL) throws -> RecentFolder {
        try #require(library.recent().first { $0.id == url.canonicalKeyPath })
    }

    @Test func finishSortRemembersSortedAt() throws {
        let a = try folder("A")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var session = try saveSession(for: a)
        session.sortedAt = date
        library.finishSort(session)
        #expect(try entry(a).sortedAt == date)
        #expect(try entry(a).photoCount == 1)
    }

    @Test func isSortedReadsTheSession() throws {
        let a = try folder("A"), b = try folder("B")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try saveSession(for: a, sortedAt: date)
        try saveSession(for: b)
        #expect(library.isSorted(a) == date)
        #expect(library.isSorted(b) == nil)
        #expect(library.isSorted(try folder("C")) == nil)
        // A moved folder: the session is still at the old path.
        #expect(library.isSorted(try folder("Moved"), previousPath: a.canonicalKeyPath) == date)
    }

    @Test func startNewSortDeletesSessionAndJournal() async throws {
        let (source, copy) = try sortedFolder()
        try await library.startNewSort(source)
        #expect(try sessions.load(source: source) == nil)
        #expect(!FileManager.default.fileExists(atPath: sessions.directory(for: source).path))
        #expect(try entry(source).sortedAt == nil)
        #expect(library.isSorted(source) == nil)
        // The sorted files stay. The app does not track them (spec 9.1).
        #expect(FileManager.default.fileExists(atPath: copy.path))
        guard case .new = try library.prepareOpen(source) else { Issue.record("expected .new"); return }
    }

    @Test func startNewSortDeletesSessionOfPreviousPath() async throws {
        let (old, _) = try sortedFolder("Old")
        let new = try folder("New")
        try await library.startNewSort(new, previousPath: old.canonicalKeyPath)
        #expect(try sessions.load(source: old) == nil)
        guard case .new = try library.prepareOpen(new, previousPath: old.canonicalKeyPath) else {
            Issue.record("expected .new"); return
        }
        #expect(library.recent().map(\.path) == [new.canonicalKeyPath])
    }

    @Test func startNewSortRefusesAnUnfinishedSort() async throws {
        let (source, copy) = try sortedFolder()
        // A stopped sort: the journal has no done line.
        let journal = library.journal(for: source)
        let entries = try journal.read().filter { $0.op != .done }
        try FileManager.default.removeItem(at: sessions.directory(for: source).appending(path: "journal.jsonl"))
        for e in entries { try journal.append(e) }

        await #expect(throws: SortError.unfinishedLastSort) { try await self.library.startNewSort(source) }
        #expect(try sessions.load(source: source)?.sortedAt != nil)
        #expect(try journal.lastIsComplete() == false)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        // The unfinished journal of the old path of a moved folder counts too.
        await #expect(throws: SortError.movedAfterUnfinishedSort(oldPath: source.canonicalKeyPath)) {
            try await self.library.startNewSort(try self.folder("New"), previousPath: source.canonicalKeyPath)
        }
        #expect(try sessions.load(source: source) != nil)
    }

    /// Rewrites the journal of `source` without its `done` line, as after a stopped sort.
    private func makeUnfinished(_ source: URL) throws {
        let journal = library.journal(for: source)
        let entries = try journal.read().filter { $0.op != .done }
        try FileManager.default.removeItem(at: sessions.directory(for: source).appending(path: "journal.jsonl"))
        for e in entries { try journal.append(e) }
    }

    /// Final review M7: the Welcome screen asks this before "Start a new sort?".
    @Test func checkLastSortFinishedFindsAnUnfinishedSort() throws {
        let (source, _) = try sortedFolder()
        try library.checkLastSortFinished(source)
        try library.checkLastSortFinished(try folder("Plain"))
        try makeUnfinished(source)
        #expect(throws: SortError.unfinishedLastSort) { try self.library.checkLastSortFinished(source) }
        #expect(throws: SortError.movedAfterUnfinishedSort(oldPath: source.canonicalKeyPath)) {
            try self.library.checkLastSortFinished(try self.folder("Moved"), previousPath: source.canonicalKeyPath)
        }
    }

    /// Final review I3: a moved folder whose last sort did not finish is not relinked. The old session,
    /// journal, and recent entry stay, so the user can move the folder back and undo.
    @Test func movedFolderWithUnfinishedSortIsNotRelinked() throws {
        let (old, copy) = try sortedFolder("Old")
        try makeUnfinished(old)
        let oldPath = old.canonicalKeyPath
        let new = dir.url.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: new)

        #expect(throws: SortError.movedAfterUnfinishedSort(oldPath: oldPath)) {
            try self.library.prepareOpen(new, previousPath: oldPath)
        }
        #expect(try sessions.load(source: old)?.sortedAt != nil)
        #expect(try sessions.load(source: new) == nil)
        #expect(try library.journal(for: old).lastIsComplete() == false)
        #expect(library.recent().map(\.path) == [oldPath])
        #expect(FileManager.default.fileExists(atPath: copy.path))

        // Moved back: Undo Last Sort shows and works.
        try FileManager.default.moveItem(at: new, to: old)
        #expect(library.canUndoLastSort(try entry(old)))
    }

    /// Final review M1: the service asks the repository, not `FileManager`.
    @Test func journalExistsAfterTheFirstLine() throws {
        let a = try folder("A")
        let journal = library.journal(for: a)
        #expect(!journal.exists)
        try journal.append(JournalEntry(op: .done, source: nil, destination: nil, time: .now))
        #expect(journal.exists)
    }

    /// The quit guard asks this (final review M4).
    @Test func isSortRunningWhileTheSortServiceRuns() async throws {
        #expect(!library.isSortRunning)
        let other = try folder("Other")
        let photo = other.appending(path: "p.jpg")
        try Data(repeating: 7, count: 10).write(to: photo)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)],
                                              ofItemAtPath: photo.path)
        let session = try saveSession(for: other)
        let plan = try sortService.plan(session, source: other, options: .defaults(source: other))
        let running = sortService.run(plan, mode: .copy, journal: library.journal(for: other),
                                      stop: { Thread.sleep(forTimeInterval: 0.3); return true })
        let drain = Task { for try await _ in running {} }
        try await Task.sleep(for: .milliseconds(100))
        #expect(library.isSortRunning)
        _ = await drain.result
        await library.waitUntilSortIdle()
        #expect(!library.isSortRunning)
    }

    @Test func startNewSortWaitsUntilTheSortServiceIsIdle() async throws {
        let (source, _) = try sortedFolder()
        // Another sort holds the service for 0.3 s, then stops before its first file.
        let other = try folder("Other")
        // Same size and time as the saved scan, so the sort precheck passes.
        let photo = other.appending(path: "p.jpg")
        try Data(repeating: 7, count: 10).write(to: photo)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)],
                                              ofItemAtPath: photo.path)
        let otherSession = try saveSession(for: other)
        let plan = try sortService.plan(otherSession, source: other, options: .defaults(source: other))
        let blocker = sortService.run(plan, mode: .copy, journal: library.journal(for: other),
                                      stop: { Thread.sleep(forTimeInterval: 0.3); return true })
        let drain = Task { for try await _ in blocker {} }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        try await library.startNewSort(source)
        #expect(ContinuousClock.now - start >= .milliseconds(150))
        #expect(try sessions.load(source: source) == nil)
        _ = await drain.result
    }

    @Test func canUndoLastSortNeedsSortedAtAndJournal() throws {
        let (source, _) = try sortedFolder()
        #expect(library.canUndoLastSort(try entry(source)))
        let plain = try folder("Plain")
        try saveSession(for: plain)
        library.remember(plain, photoCount: 1, sortedAt: nil)
        #expect(!library.canUndoLastSort(try entry(plain)))
        // Sorted, but the journal is gone.
        let (other, _) = try sortedFolder("Other")
        try FileManager.default.removeItem(at: sessions.directory(for: other).appending(path: "journal.jsonl"))
        #expect(!library.canUndoLastSort(try entry(other)))
    }

    @Test func undoLastSortReversesTheJournalAndClearsSortedAt() async throws {
        let (source, copy) = try sortedFolder()
        try await library.undoLastSort(try entry(source))
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "p.jpg").path))
        #expect(try library.journal(for: source).lastIsComplete() == nil)
        // The session stays, so the folder opens in review without a new scan.
        let session = try #require(try sessions.load(source: source))
        #expect(session.sortedAt == nil)
        #expect(try entry(source).sortedAt == nil)
        #expect(try entry(source).photoCount == 1)
        #expect(!library.canUndoLastSort(try entry(source)))
    }

    @Test func undoLastSortWithoutJournalClearsSortedAtSilently() async throws {
        let (source, _) = try sortedFolder()
        try FileManager.default.removeItem(at: sessions.directory(for: source).appending(path: "journal.jsonl"))
        try await library.undoLastSort(try entry(source))
        #expect(try sessions.load(source: source)?.sortedAt == nil)
        #expect(try entry(source).sortedAt == nil)
    }

    @Test func undoLastSortWithConflictsThrowsAndClearsSortedAt() async throws {
        let (source, copy) = try sortedFolder()
        // The original is gone, so the copy is the only one: undo keeps it.
        try FileManager.default.removeItem(at: source.appending(path: "p.jpg"))
        await #expect(throws: SortError.undoConflicts([copy])) {
            try await self.library.undoLastSort(try self.entry(source))
        }
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(try sessions.load(source: source)?.sortedAt == nil)
        #expect(try entry(source).sortedAt == nil)
    }

    @Test func undoLastSortOfOpenReviewClearsItsSortedAt() async throws {
        let (source, copy) = try sortedFolder()
        let session = try #require(try sessions.load(source: source))
        let review = try await library.openReview(session: session, source: source)
        try await library.undoLastSort(review: review)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(review.session.sortedAt == nil)
        #expect(try sessions.load(source: source)?.sortedAt == nil)
        #expect(try entry(source).sortedAt == nil)
    }

    @Test func movedSortedFolderHidesUndo() throws {
        let (old, _) = try sortedFolder("Old")
        let new = dir.url.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: new)
        // The bookmark finds the new place, but the journal holds the old paths.
        let moved = try entry(old)
        #expect(library.resolve(moved)?.canonicalKeyPath == new.canonicalKeyPath)
        #expect(!library.canUndoLastSort(moved))
    }

    @Test func clearRemovesAllEntries() throws {
        try saveSession(for: try folder("A"))
        library.remember(try folder("A"), photoCount: 1, sortedAt: nil)
        library.remember(try folder("B"), photoCount: 1, sortedAt: nil)
        #expect(library.recent().count == 2)
        library.clearRecent()
        #expect(library.recent().isEmpty)
    }

    @Test func removeRecentKeepsSession() throws {
        let (source, _) = try sortedFolder()
        library.remember(try folder("B"), photoCount: 1, sortedAt: nil)
        library.removeRecent(try entry(source))
        #expect(library.recent().map(\.path) == [try folder("B").canonicalKeyPath])
        #expect(try sessions.load(source: source) != nil)
        #expect(library.journal(for: source).exists)
    }

    @Test func undoLastSortBySourceWithoutRecentEntry() async throws {
        let (source, copy) = try sortedFolder()
        library.removeRecent(try entry(source))
        #expect(library.canUndoLastSort(source: source))
        try await library.undoLastSort(source: source)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(try Data(contentsOf: source.appending(path: "p.jpg")) == Data([1, 2, 3]))
        #expect(try sessions.load(source: source)?.sortedAt == nil)
        #expect(try entry(source).sortedAt == nil)
        #expect(try entry(source).photoCount == 1)
        #expect(!library.canUndoLastSort(source: source))
    }

    @Test func canUndoLastSortBySourceIsFalseForMovedFolder() throws {
        let (old, _) = try sortedFolder("Old")
        let new = dir.url.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: new)
        #expect(!library.canUndoLastSort(source: new))
        // A journal that holds paths of another folder does not count either.
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sessions.directory(for: old), to: sessions.directory(for: new))
        #expect(!library.canUndoLastSort(source: new))
    }

    @Test func relinkedSortedFolderShowsSortedButNoUndo() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let (old, _) = try sortedFolder("Old", at: date)
        let new = dir.url.appending(path: "New", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: new)
        guard case .existing(let s) = try library.prepareOpen(new, previousPath: old.canonicalKeyPath) else {
            Issue.record("expected .existing"); return
        }
        #expect(s.sortedAt == date)
        let relinked = try entry(new)
        #expect(relinked.sortedAt == date)
        #expect(!library.canUndoLastSort(relinked))
        #expect(try library.journal(for: new).lastIsComplete() == nil)
    }

    // MARK: - Start Over (spec 3.3)

    @Test func startOverKeepsEmbeddingsAndHashes() async throws {
        let a = try folder("A")
        try saveSession(for: a)
        let dir = sessions.directory(for: a)
        let kept = ["embeddings.f32", "embeddings.index.json", "hashes.json"].map { dir.appending(path: $0) }
        for file in kept { try Data([1]).write(to: file) }
        let photo = a.appending(path: "p.jpg")
        try Data([1, 2, 3]).write(to: photo)

        try await library.startOver(a)

        #expect(try sessions.load(source: a) == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "session.json").path))
        for file in kept { #expect(FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent)") }
        #expect(FileManager.default.fileExists(atPath: photo.path))
        #expect(try entry(a).sortedAt == nil)
        #expect(try entry(a).photoCount == 1)
        guard case .new = try library.prepareOpen(a) else { Issue.record("expected .new"); return }
    }

    @Test func startOverArchivesJournal() async throws {
        let (source, copy) = try sortedFolder()
        #expect(library.canUndoLastSort(try entry(source)))

        try await library.startOver(source)

        #expect(!library.journal(for: source).exists)
        #expect(!library.canUndoLastSort(try entry(source)))
        #expect(!library.canUndoLastSort(source: source))
        let names = try FileManager.default.contentsOfDirectory(atPath: sessions.directory(for: source).path)
        #expect(names.contains { $0.hasPrefix("journal.") && $0.hasSuffix(".startover.jsonl") })
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func startOverRefusesUnfinishedSort() async throws {
        let (source, _) = try sortedFolder()
        try makeUnfinished(source)

        await #expect(throws: SortError.unfinishedLastSort) { try await self.library.startOver(source) }

        #expect(FileManager.default.fileExists(
            atPath: sessions.directory(for: source).appending(path: "session.json").path))
        #expect(try sessions.load(source: source)?.sortedAt != nil)
        #expect(library.journal(for: source).exists)
    }

    @Test func startOverWithoutSessionOrJournal() async throws {
        let a = try folder("A")
        try await library.startOver(a)
        #expect(try entry(a).photoCount == 0)
    }

    @Test func openReviewLoadsSession() async throws {
        let a = try folder("A")
        let session = try saveSession(for: a)
        let review = try await library.openReview(session: session, source: a)
        #expect(review.session == session)
    }
}

@Test func modelSizeFromStem() {
    #expect(MobileCLIPSize(modelStem: "mobileclip_s2") == .s2)
    #expect(MobileCLIPSize(modelStem: "mobileclip_blt") == .b)
    #expect(MobileCLIPSize(modelStem: "nope") == nil)
}
