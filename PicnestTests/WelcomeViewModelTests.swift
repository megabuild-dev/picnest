import AppKit
import Foundation
import PicnestCore
import SwiftUI
import Testing
@testable import Picnest

@MainActor
struct WelcomeViewModelTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let environment: AppEnvironment
    private let app: AppModel
    private let viewModel: WelcomeViewModel

    init() throws {
        temp = try TempDir()
        environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
        app = AppModel(environment: environment)
        viewModel = WelcomeViewModel(app: app, library: environment.library, locale: Locale(identifier: "en_US"))
    }

    /// Saves a session with `count` photos for `source`.
    @discardableResult
    private func saveSession(for source: URL, count: Int, sortedAt: Date? = nil) throws -> Session {
        let category = Category(id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 0)
        let files = (0..<count).map {
            MediaFile(id: "p\($0).jpg", relativePath: "p\($0).jpg", kind: .image, size: 10,
                      modified: Date(timeIntervalSince1970: 1000))
        }
        let assignment = Assignment(
            categoryID: category.id, score: 1, secondCategoryID: nil, secondScore: nil, percent: 100, uncertain: false)
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [category],
            states: Dictionary(uniqueKeysWithValues: files.map { ($0.id, PhotoState.auto(assignment)) }),
            scan: ScanResult(media: files, dates: [:], skipped: [:]), sortedAt: sortedAt)
        try environment.sessions.save(session)
        return session
    }

    /// Noon on 2026-10-21 in the current time zone, so the date text does not depend on the time zone.
    private let sortDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!

    /// A sorted folder: `p0.jpg` and its copy in `<name> - sorted/Food/`, a complete journal, a session
    /// with `sortedAt`, and a recent folder entry with `sortedAt`.
    @discardableResult
    private func sortedFolder(_ name: String = "Sorted") throws -> (source: URL, copy: URL) {
        let source = try temp.folder(name)
        try Data([1, 2, 3]).write(to: source.appending(path: "p0.jpg"))
        let made = try temp.folder(name + " - sorted/Food")
        let copy = made.appending(path: "p0.jpg")
        try Data([1, 2, 3]).write(to: copy)
        let journal = environment.library.journal(for: source)
        try journal.append(JournalEntry(op: .mkdir, source: nil, destination: made.path, time: sortDate))
        try journal.append(JournalEntry(op: .copy, source: source.appending(path: "p0.jpg").path,
                                        destination: copy.path, time: sortDate))
        try journal.append(JournalEntry(op: .done, source: nil, destination: nil, time: sortDate))
        try saveSession(for: source, count: 1, sortedAt: sortDate)
        environment.library.remember(source, photoCount: 1, sortedAt: sortDate)
        viewModel.refresh()
        return (source, copy)
    }

    private func isScanning(_ url: URL) -> Bool {
        if case .scanning(let u, _) = app.screen { return u == url }
        return false
    }

    private var isReview: Bool {
        if case .review = app.screen { return true }
        return false
    }

    private var isWelcome: Bool {
        if case .welcome = app.screen { return true }
        return false
    }

    // MARK: - choose

    @Test func chooseNewFolderStartsScan() async throws {
        let folder = try temp.folder("New")
        viewModel.choose(folder)
        await app.settled()
        #expect(isScanning(folder))
    }

    @Test func chooseFolderWithSavedSessionOpensReview() async throws {
        let folder = try temp.folder("Saved")
        try saveSession(for: folder, count: 3)
        viewModel.choose(folder)
        await app.settled()
        #expect(isReview)
        if case .review(let review, _) = app.screen {
            #expect(review.session.scan.media.count == 3)
        }
    }

    @Test func chooseRemembersFolderWithPhotoCount() async throws {
        let fresh = try temp.folder("Fresh")
        let saved = try temp.folder("Saved")
        try saveSession(for: saved, count: 3)
        viewModel.choose(fresh)
        viewModel.choose(saved)
        await app.settled()
        #expect(viewModel.recent.map(\.path) == [saved.canonicalPath, fresh.canonicalPath])
        #expect(viewModel.recent.map(\.photoCount) == [3, 0])
    }

    @Test func finishScanOpensReviewAndUpdatesCount() async throws {
        let folder = try temp.folder("Scanned")
        viewModel.choose(folder)
        await app.settled()
        #expect(viewModel.recent.first?.photoCount == 0)

        let session = try saveSession(for: folder, count: 4)
        app.finishScan(session)
        await app.settled()
        #expect(isReview)
        viewModel.refresh()
        #expect(viewModel.recent.first?.photoCount == 4)
    }

    // MARK: - recent

    @Test func recentShowsAtMostFive() throws {
        for i in 0..<7 {
            environment.library.remember(try temp.folder("F\(i)"), photoCount: i, sortedAt: nil)
        }
        viewModel.refresh()
        #expect(viewModel.recent.count == 5)
        #expect(viewModel.recent.first?.photoCount == 6)
    }

    @Test func openRecentOpensResolvedFolder() async throws {
        let folder = try temp.folder("Recent")
        environment.library.remember(folder, photoCount: 0, sortedAt: nil)
        viewModel.refresh()
        viewModel.openRecent(try #require(viewModel.recent.first))
        await app.settled()
        #expect(app.screen.scanningURL?.canonicalPath == folder.canonicalPath)
        #expect(viewModel.missingFolder == nil)
    }

    @Test func openRecentWithMissingFolderAsksToFindIt() async throws {
        let folder = try temp.folder("Gone")
        environment.library.remember(folder, photoCount: 2, sortedAt: nil)
        try FileManager.default.removeItem(at: folder)
        viewModel.refresh()
        let entry = try #require(viewModel.recent.first)
        viewModel.openRecent(entry)
        #expect(viewModel.missingFolder == entry)
        #expect(isWelcome)

        let found = try temp.folder("Found")
        viewModel.beginFindingFolder()
        viewModel.findFolder(found)
        await app.settled()
        #expect(viewModel.missingFolder == nil)
        #expect(isScanning(found))
        #expect(viewModel.recent.map(\.path) == [found.canonicalPath])
    }

    @Test func openRecentAfterMoveKeepsSession() async throws {
        let old = try temp.folder("Old")
        try saveSession(for: old, count: 3)
        environment.library.remember(old, photoCount: 3, sortedAt: nil)
        let new = temp.url.appending(path: "Moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: new)
        viewModel.refresh()

        viewModel.openRecent(try #require(viewModel.recent.first))
        await app.settled()
        #expect(isReview)
        if case .review(let review, _) = app.screen {
            #expect(review.session.sourcePath == new.canonicalPath)
            #expect(review.session.scan.media.count == 3)
        }
        #expect(viewModel.recent.map(\.path) == [new.canonicalPath])
    }

    @Test func findFolderAfterMoveKeepsSession() async throws {
        let old = try temp.folder("Lost")
        try saveSession(for: old, count: 2)
        environment.library.remember(old, photoCount: 2, sortedAt: nil)
        // A copy has a new file identity, so the bookmark cannot follow it.
        let found = temp.url.appending(path: "Found", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: old, to: found)
        try FileManager.default.removeItem(at: old)
        viewModel.refresh()
        let entry = try #require(viewModel.recent.first)
        viewModel.openRecent(entry)
        #expect(viewModel.missingFolder == entry)

        viewModel.beginFindingFolder()
        #expect(viewModel.missingFolder == nil)
        viewModel.findFolder(found)
        await app.settled()
        #expect(isReview)
        if case .review(let review, _) = app.screen {
            #expect(review.session.sourcePath == found.canonicalPath)
        }
        #expect(viewModel.recent.map(\.path) == [found.canonicalPath])
    }

    // MARK: - After a sort (spec 9.1)

    @Test func doneClosesTheSessionAndShowsSorted() async throws {
        let folder = try temp.folder("Saved")
        try saveSession(for: folder, count: 3)
        viewModel.choose(folder)
        await app.settled()
        guard case .review(let review, _) = app.screen else { Issue.record("expected review"); return }
        review.markSorted(at: sortDate)

        app.done()
        await app.settled()
        #expect(isWelcome)
        viewModel.refresh()
        let entry = try #require(viewModel.recent.first)
        #expect(entry.sortedAt == sortDate)
        #expect(viewModel.sortedText(entry) == "Sorted Oct 21, 2026")
        #expect(try environment.sessions.load(source: folder)?.sortedAt == sortDate)
    }

    @Test func unsortedFolderHasNoSortedText() throws {
        environment.library.remember(try temp.folder("Plain"), photoCount: 2, sortedAt: nil)
        viewModel.refresh()
        let entry = try #require(viewModel.recent.first)
        #expect(viewModel.sortedText(entry) == nil)
        #expect(!viewModel.canUndoLastSort(entry))
    }

    @Test func openingSortedFolderAsksToStartNewSort() async throws {
        let (folder, copy) = try sortedFolder()
        viewModel.choose(folder)
        #expect(viewModel.newSortRequest?.url == folder)
        #expect(isWelcome)
        #expect(viewModel.newSortRequest?.sortedText == "This folder was sorted on Oct 21, 2026.")
        #expect(WelcomeViewModel.newSortMessage == "If you start a new sort, the last sort can no longer be undone.")

        viewModel.cancelNewSort()
        #expect(viewModel.newSortRequest == nil)
        #expect(isWelcome)
        #expect(try environment.sessions.load(source: folder) != nil)

        viewModel.openRecent(try #require(viewModel.recent.first))
        #expect(viewModel.newSortRequest != nil)
        await viewModel.confirmNewSort()
        await app.settled()
        #expect(viewModel.newSortRequest == nil)
        #expect(app.screen.scanningURL?.canonicalPath == folder.canonicalPath)
        #expect(try environment.sessions.load(source: folder) == nil)
        #expect(viewModel.recent.first?.sortedAt == nil)
        // The sorted files stay where they are.
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func removeRecentAndClearRecent() throws {
        let (folder, _) = try sortedFolder()
        environment.library.remember(try temp.folder("Plain"), photoCount: 2, sortedAt: nil)
        viewModel.refresh()
        viewModel.removeRecent(try #require(viewModel.recent.first { $0.path == folder.canonicalPath }))
        #expect(viewModel.recent.map(\.path) == [try temp.folder("Plain").canonicalPath])
        #expect(try environment.sessions.load(source: folder) != nil)
        viewModel.clearRecent()
        #expect(viewModel.recent.isEmpty)
        #expect(try environment.sessions.load(source: folder) != nil)
    }

    @Test func reopenSortedFolderDialogOffersUndo() throws {
        let (folder, _) = try sortedFolder()
        viewModel.choose(folder)
        let request = try #require(viewModel.newSortRequest)
        #expect(request.sortedText == "This folder was sorted on Oct 21, 2026.")
        #expect(request.canUndo)
    }

    @Test func reopenMovedSortedFolderHidesUndo() throws {
        let (folder, _) = try sortedFolder()
        let entry = try #require(viewModel.recent.first)
        try FileManager.default.moveItem(at: folder, to: temp.url.appending(path: "Moved", directoryHint: .isDirectory))
        viewModel.openRecent(entry)
        #expect(try #require(viewModel.newSortRequest).canUndo == false)
    }

    @Test func undoFromDialogOpensReview() async throws {
        let (folder, copy) = try sortedFolder()
        viewModel.choose(folder)
        await viewModel.undoFromDialog()
        await app.settled()
        #expect(viewModel.newSortRequest == nil)
        #expect(viewModel.undoMessage == nil)
        #expect(!app.isUndoingSort)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(isReview)
        #expect(try environment.sessions.load(source: folder)?.sortedAt == nil)
    }

    @Test func undoLastSortFromRecentListKeepsSession() async throws {
        let (folder, copy) = try sortedFolder()
        let entry = try #require(viewModel.recent.first)
        #expect(viewModel.sortedText(entry) == "Sorted Oct 21, 2026")
        #expect(viewModel.canUndoLastSort(entry))

        await viewModel.undoLastSort(entry)
        #expect(viewModel.undoMessage == nil)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        let after = try #require(viewModel.recent.first)
        #expect(after.sortedAt == nil)
        #expect(viewModel.sortedText(after) == nil)
        #expect(!viewModel.canUndoLastSort(after))

        // The session stays: the folder opens in review, with no question and no scan.
        viewModel.choose(folder)
        #expect(viewModel.newSortRequest == nil)
        await app.settled()
        #expect(isReview)
    }

    @Test func undoLastSortWithConflictsShowsTheFirstNames() async throws {
        let (folder, copy) = try sortedFolder()
        try FileManager.default.removeItem(at: folder.appending(path: "p0.jpg"))
        await viewModel.undoLastSort(try #require(viewModel.recent.first))
        #expect(viewModel.undoMessage
            == "Some files could not be put back. They are still in the sorted folder: p0.jpg.")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(viewModel.recent.first?.sortedAt == nil)
    }

    @Test func undoConflictTextShowsAtMostThreeNames() {
        let urls = ["a.jpg", "b.jpg", "c.jpg", "d.jpg"].map { URL(filePath: "/tmp/\($0)") }
        #expect(SortMessages.text(for: SortError.undoConflicts(urls))
            == "Some files could not be put back. They are still in the sorted folder: a.jpg, b.jpg, c.jpg…")
    }

    @Test func movedSortedFolderShowsSortedWithoutUndo() throws {
        let (folder, _) = try sortedFolder()
        try FileManager.default.moveItem(at: folder, to: temp.url.appending(path: "Moved", directoryHint: .isDirectory))
        viewModel.refresh()
        let entry = try #require(viewModel.recent.first)
        #expect(viewModel.sortedText(entry) == "Sorted Oct 21, 2026")
        #expect(!viewModel.canUndoLastSort(entry))
    }

    /// Rewrites the journal of `source` without its `done` line, as after a stopped sort.
    private func makeUnfinished(_ source: URL) throws {
        let journal = environment.library.journal(for: source)
        let entries = try journal.read().filter { $0.op != .done }
        try FileManager.default.removeItem(at: environment.sessions.directory(for: source).appending(path: "journal.jsonl"))
        for e in entries { try journal.append(e) }
    }

    /// Final review M7: no "Start a new sort?" question that can only end in a refusal.
    @Test func startNewSortIsRefusedAfterAnUnfinishedSort() async throws {
        let (folder, copy) = try sortedFolder()
        try makeUnfinished(folder)
        viewModel.choose(folder)
        #expect(viewModel.newSortRequest == nil)
        await app.settled()
        #expect(viewModel.errorMessage == "The last sort did not finish. Click Undo Last Sort first.")
        #expect(isWelcome)
        #expect(try environment.sessions.load(source: folder)?.sortedAt != nil)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(viewModel.canUndoLastSort(try #require(viewModel.recent.first)))
    }

    /// Final review I3: a moved folder whose last sort did not finish says where to move it back.
    @Test func movedFolderWithUnfinishedSortSaysMoveItBack() async throws {
        let (old, copy) = try sortedFolder("Old")
        try makeUnfinished(old)
        let entry = try #require(viewModel.recent.first)
        let moved = temp.url.appending(path: "Moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: moved)
        viewModel.refresh()
        #expect(!viewModel.canUndoLastSort(entry))

        viewModel.openRecent(entry)
        await app.settled()
        let oldText = ReviewViewModel.abbreviate(entry.path, home: NSHomeDirectory())
        #expect(viewModel.errorMessage
            == "This folder moved after a sort that did not finish. Move it back to \(oldText), then click Undo Last Sort.")
        #expect(viewModel.newSortRequest == nil)
        #expect(isWelcome)
        // Nothing is relinked: the old entry, session, and journal stay.
        #expect(viewModel.recent.map(\.path) == [entry.path])
        #expect(try environment.sessions.load(source: old)?.sortedAt != nil)
        #expect(try environment.library.journal(for: old).lastIsComplete() == false)
        #expect(FileManager.default.fileExists(atPath: copy.path))

        // AppModel refuses too, with the same text.
        viewModel.errorMessage = nil
        app.open(moved, previousPath: entry.path)
        await app.settled()
        #expect(viewModel.errorMessage?.hasSuffix("Move it back to \(oldText), then click Undo Last Sort.") == true)
        #expect(try environment.sessions.load(source: moved) == nil)

        // Moved back: Undo Last Sort shows.
        try FileManager.default.moveItem(at: moved, to: old)
        viewModel.refresh()
        #expect(viewModel.canUndoLastSort(try #require(viewModel.recent.first)))
    }

    @Test func everythingWaitsWhileAnUndoRuns() async throws {
        let (_, copy) = try sortedFolder()
        let entry = try #require(viewModel.recent.first)
        #expect(app.beginUndo())
        #expect(!app.beginUndo())  // 1 undo for the whole app.
        #expect(viewModel.isBusy)
        #expect(viewModel.drop([try temp.folder("Dropped")]) == false)
        viewModel.choose(try temp.folder("Chosen"))
        #expect(isWelcome)
        #expect(viewModel.newSortRequest == nil)
        await viewModel.undoLastSort(entry)
        #expect(FileManager.default.fileExists(atPath: copy.path))

        app.endUndo()
        #expect(!viewModel.isBusy)
        await viewModel.undoLastSort(entry)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    /// Lays out the Welcome screen with a sorted folder row. Catches crashes in the view code.
    @Test func welcomeWithSortedFolderLaysOut() throws {
        try sortedFolder()
        environment.library.remember(try temp.folder("Plain"), photoCount: 2, sortedAt: nil)
        viewModel.refresh()
        let view = NSHostingView(rootView: WelcomeView(model: viewModel))
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0)
    }

    // MARK: - drop

    @Test func dropAcceptsFolder() async throws {
        let folder = try temp.folder("Dropped")
        #expect(viewModel.drop([folder]))
        await app.settled()
        #expect(isScanning(folder))
    }

    @Test func dropIgnoresFiles() throws {
        let file = temp.url.appending(path: "photo.jpg")
        try Data([1, 2, 3]).write(to: file)
        #expect(viewModel.drop([file]) == false)
        #expect(isWelcome)
        #expect(viewModel.recent.isEmpty)
    }

    @Test func dropIgnoredWhileOpening() async throws {
        let saved = try temp.folder("Saved")
        try saveSession(for: saved, count: 1)
        viewModel.choose(saved)
        #expect(viewModel.isOpening)
        #expect(viewModel.drop([try temp.folder("Other")]) == false)
        await app.settled()
        #expect(isReview)
    }

    @Test func bundleModelStemMapsToSize() {
        #expect(AppEnvironment.modelSize(in: .main) == .s2)
    }

    @Test func showWelcomeGoesBack() async throws {
        let folder = try temp.folder("Back")
        viewModel.choose(folder)
        await app.settled()
        app.showWelcome()
        #expect(isWelcome)
    }
}

private extension URL {
    /// Same form as the core's canonical key path: symlinks resolved, no trailing slash.
    var canonicalPath: String {
        let path = resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

private extension AppModel.Screen {
    var scanningURL: URL? {
        if case .scanning(let url, _) = self { return url }
        return nil
    }
}
