import Foundation
import PicnestCore
import Testing
@testable import Picnest

/// Screens of `AppModel`: review after a scan or a reopen, and **Start Over…** (spec 3.3, 3.7).
@MainActor
struct AppModelTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let environment: AppEnvironment
    private let app: AppModel
    /// Holds an undo of a sort while it runs, so a test can act during it.
    private let sortOps = GatedFileOps()
    private let food = PicnestCore.Category(
        id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 0)

    init() throws {
        temp = try TempDir()
        environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults,
            sortFileOps: sortOps)
        app = AppModel(environment: environment)
    }

    /// Saves a session of 1 photo, `a.jpg` (a manual Food pick), for a new folder `name`.
    @discardableResult
    private func savedFolder(_ name: String = "Saved") throws -> (source: URL, session: Session) {
        let source = try temp.folder(name)
        try Data([0]).write(to: source.appending(path: "a.jpg"))
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [food],
            states: ["a.jpg": .manual(food.id)],
            scan: ScanResult(media: [MediaFile(id: "a.jpg", relativePath: "a.jpg", kind: .image, size: 1,
                                               modified: Date(timeIntervalSince1970: 1000))],
                             dates: [:], skipped: [:]),
            sortedAt: nil)
        try environment.sessions.save(session)
        return (source, session)
    }

    /// Adds a complete journal of a sort that copied `a.jpg` of `source` to `<source> - sorted/Food/`.
    private func addSortJournal(_ source: URL) throws {
        let made = try temp.folder(source.lastPathComponent + " - sorted/Food")
        let copy = made.appending(path: "a.jpg")
        try Data([0]).write(to: copy)
        let journal = environment.library.journal(for: source)
        try journal.append(JournalEntry(op: .mkdir, source: nil, destination: made.path, time: .now))
        try journal.append(JournalEntry(op: .copy, source: source.appending(path: "a.jpg").path,
                                        destination: copy.path, time: .now))
        try journal.append(JournalEntry(op: .done, source: nil, destination: nil, time: .now))
    }

    /// Opens the saved folder `Saved` in review. Starts an undo of its sort and holds it while it runs.
    /// Release `sortOps.removeGate` and await the task to end the undo.
    private func reviewWithRunningUndo() async throws -> (source: URL, undo: Task<Void, any Error>) {
        let (source, _) = try savedFolder()
        try addSortJournal(source)
        app.open(source)
        await app.settled()
        sortOps.removeGate.hold()
        let library = environment.library
        let undo = Task { try await library.undoLastSort(source: source) }
        try await sortOps.removeGate.untilWaiting()
        return (source, undo)
    }

    /// A view model of the open review.
    private func reviewModel() throws -> ReviewViewModel {
        enum Failure: Error { case notInReview }
        guard case .review(let review, _) = app.screen else { throw Failure.notInReview }
        return ReviewViewModel(
            review: review, classify: environment.classifyService, thumbnails: environment.thumbnails,
            library: environment.library, app: app, onRescan: app.rescan)
    }

    /// `afterScan` of the review screen, or nil on another screen.
    private var afterScan: Bool? {
        if case .review(_, let afterScan) = app.screen { return afterScan }
        return nil
    }

    // MARK: - Review after a scan (spec 3.7)

    @Test func finishScanOpensReviewAfterScan() async throws {
        let (_, session) = try savedFolder()
        app.finishScan(session)
        await app.settled()
        #expect(afterScan == true)
    }

    @Test func openSavedSessionIsNotAfterScan() async throws {
        let (source, _) = try savedFolder()
        app.open(source)
        await app.settled()
        #expect(afterScan == false)
    }

    // MARK: - Start Over… (spec 3.3)

    @Test func startOverRunsFirstScan() async throws {
        let (source, _) = try savedFolder()
        app.open(source)
        await app.settled()
        try #require(afterScan != nil)

        try await app.startOver()
        guard case .scanning(let url, let rescanOf) = app.screen else {
            Issue.record("Expected scanning, got \(app.screen)"); return
        }
        #expect(url.lastPathComponent == "Saved")
        #expect(rescanOf == nil)
        #expect(try environment.sessions.load(source: source) == nil)
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "a.jpg").path))
    }

    @Test func startOverAfterUnfinishedSortThrowsAndStaysOnReview() async throws {
        let (source, _) = try savedFolder()
        try environment.library.journal(for: source).append(
            JournalEntry(op: .mkdir, source: nil, destination: temp.url.appending(path: "x").path, time: .now))
        app.open(source)
        await app.settled()

        await #expect(throws: SortError.self) { try await app.startOver() }
        #expect(!app.isStartingOver)
        #expect(try reviewModel().canStartOver)
        #expect(afterScan == false)
        #expect(try environment.sessions.load(source: source) != nil)

        // The review still saves after the failed start over.
        guard case .review(let review, _) = app.screen else { Issue.record("Expected review"); return }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        review.markSorted(at: date)
        await review.settled()
        #expect(try environment.sessions.load(source: source)?.sortedAt == date)
    }

    /// Final review: a review change after the start over cannot write the deleted session again.
    @Test func reviewDoesNotSaveAfterStartOver() async throws {
        let (source, _) = try savedFolder()
        app.open(source)
        await app.settled()
        guard case .review(let review, _) = app.screen else { Issue.record("Expected review"); return }

        try await app.startOver()
        review.markSorted(at: Date(timeIntervalSince1970: 1_800_000_000))
        await review.settled()
        #expect(try environment.sessions.load(source: source) == nil)
    }

    // MARK: - No overlap (spec 3.3)

    @Test func rescanSortAndStartOverAreOffWhileASortRuns() async throws {
        let (_, undo) = try await reviewWithRunningUndo()
        let model = try reviewModel()
        #expect(!app.isUndoingSort)
        #expect(!model.canSortOrRescan)
        #expect(!model.canStartOver)
        model.requestStartOver()
        #expect(!model.isConfirmingStartOver)
        sortOps.removeGate.release()
        try await undo.value
        #expect(model.canSortOrRescan)
        #expect(model.canStartOver)
    }

    @Test func secondStartOverAndRescanAreRefusedWhileStartingOver() async throws {
        let (_, undo) = try await reviewWithRunningUndo()
        let model = try reviewModel()
        let first = Task { try await app.startOver() }
        try await waitUntil { app.isStartingOver }
        #expect(!model.canStartOver)
        #expect(!model.canSortOrRescan)
        // Returns at once while the undo is held: a second start over would wait for the undo, and this
        // test would never reach the release below.
        try await app.startOver()
        app.rescan()               // Refused, so it cannot drop the start over.
        #expect(app.isStartingOver)

        sortOps.removeGate.release()
        try await undo.value
        await app.settled()        // Waits for the start over.
        try await first.value
        #expect(!app.isStartingOver)
        guard case .scanning(_, nil) = app.screen else { Issue.record("Expected a first scan, got \(app.screen)"); return }
        // The session file is not checked: this test undoes by path, and that undo saves the session at its end.
        #expect(environment.library.recent().first?.photoCount == 1)
    }

    @Test func startOverClearsTheFlagWhenTheAppLeavesTheReview() async throws {
        let (_, undo) = try await reviewWithRunningUndo()
        let first = Task { try await app.startOver() }
        try await waitUntil { app.isStartingOver }
        app.showWelcome()
        sortOps.removeGate.release()
        try await undo.value
        try await first.value
        #expect(!app.isStartingOver)
        guard case .welcome = app.screen else { Issue.record("Expected welcome, got \(app.screen)"); return }
    }
}
