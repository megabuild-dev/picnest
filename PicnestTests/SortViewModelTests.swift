import AppKit
import Foundation
import PicnestCore
import SwiftUI
import Testing
@testable import Picnest

@MainActor
@Suite(.serialized)
struct SortViewModelTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let environment: AppEnvironment
    private let food = PicnestCore.Category(
        id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 0)
    private let documents = PicnestCore.Category(
        id: UUID(), displayName: "Documents", emoji: "🧾", prompts: ["documents"], exampleIDs: [], order: 1)
    private static let locale = Locale(identifier: "en_US")

    init() throws {
        temp = try TempDir()
        environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
    }

    // MARK: - Fixtures

    private func uncertain(_ c: PicnestCore.Category) -> PhotoState {
        .auto(Assignment(categoryID: c.id, score: 0.3, secondCategoryID: nil, secondScore: nil, percent: 40,
                         uncertain: true))
    }

    /// Real files in `<temp>/Photos`: a.jpg and b.jpg are Food, c.jpg is Documents, d.jpg is Don't move.
    /// With `notSure`, c.jpg is a not-sure guess of Documents instead of a manual pick.
    private func makeSession(notSure: Bool = false, files: [String] = ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
        throws -> (session: Session, source: URL)
    {
        let source = try temp.folder("Photos")
        var media: [MediaFile] = []
        var dates: [MediaID: PhotoDate] = [:]
        for (i, name) in files.enumerated() {
            let url = source.appending(path: name, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: UInt8(truncatingIfNeeded: i), count: 10 + i).write(to: url)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            media.append(MediaFile(id: name, relativePath: name, kind: .image, size: Int64(values.fileSize!),
                                   modified: values.contentModificationDate!))
            let day = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 5, day: 12 + i, hour: 12))!
            dates[name] = PhotoDate(date: day, source: .exif)
        }
        var states: [MediaID: PhotoState] = [:]
        for (i, name) in files.enumerated() {
            switch i % 4 {
            case 0, 1: states[name] = .manual(food.id)
            case 2: states[name] = notSure ? uncertain(documents) : .manual(documents.id)
            default: states[name] = .dontMove
            }
        }
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [food, documents],
            states: states, scan: ScanResult(media: media, dates: dates, skipped: [:]), sortedAt: nil)
        return (session, source)
    }

    private func makeReview(_ session: Session, source: URL) -> ReviewService {
        ReviewService(
            session: session, source: source, images: [:], prompts: [:], classify: environment.classifyService,
            sessions: environment.sessions,
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")))
    }

    private func makeModel(_ session: Session, source: URL, onDone: @escaping () -> Void = {})
        async -> (SortViewModel, ReviewService)
    {
        let review = makeReview(session, source: source)
        let model = SortViewModel(
            review: review, sortService: environment.sortService, library: environment.library, locale: Self.locale,
            onDone: onDone)
        await model.load()
        return (model, review)
    }

    private func makeModel(notSure: Bool = false) async throws -> SortViewModel {
        let (session, source) = try makeSession(notSure: notSure)
        return await makeModel(session, source: source).0
    }

    /// 2,401 photos (no files on disk): 343 in each of 7 categories.
    private func bigSession() throws -> (Session, URL) {
        let source = try temp.folder("Zalo export")
        let categories = (0..<7).map {
            PicnestCore.Category(id: UUID(), displayName: "C\($0)", emoji: "", prompts: [], exampleIDs: [], order: $0)
        }
        var media: [MediaFile] = []
        var states: [MediaID: PhotoState] = [:]
        for i in 0..<2401 {
            let id = String(format: "p%04d.jpg", i)
            media.append(MediaFile(id: id, relativePath: id, kind: .image, size: 1, modified: Date(timeIntervalSince1970: 0)))
            states[id] = .manual(categories[i % 7].id)
        }
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: categories,
            states: states, scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil)
        return (session, source)
    }

    // MARK: - Editing

    @Test func titleCountsPhotosAndFolders() async throws {
        let (session, source) = try bigSession()
        let (model, _) = await makeModel(session, source: source)
        #expect(model.title == "Sort 2,401 photos into 7 folders")
    }

    @Test func defaultsAreCopyAndSortedFolderNextToSource() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        #expect(model.options == SortOptions.defaults(source: source))
        #expect(model.title == "Sort 3 photos into 2 folders")
        #expect(model.subtitle == "1 photo stays in the source folder.")
        #expect(model.state == .editing)
        #expect(model.canSort)
    }

    @Test func sortButtonTitleFollowsMode() async throws {
        let (session, source) = try bigSession()
        let (model, _) = await makeModel(session, source: source)
        #expect(model.sortButtonTitle == "Sort")
        model.options.mode = .move
        await model.planned()
        #expect(model.sortButtonTitle == "Move 2,401 Photos")
    }

    @Test func notSureChoiceShowsOnlyWithNotSurePhotos() async throws {
        #expect(try await makeModel(notSure: false).showNotSureChoice == false)
        let model = try await makeModel(notSure: true)
        #expect(model.showNotSureChoice)
        #expect(model.notSureHeader == "1 photo still \"Not sure\":")
    }

    @Test func previewShowsFirstFoldersWithCounts() async throws {
        let model = try await makeModel()
        #expect(model.previewLines == [
            "Photos - sorted/",
            "├ Food/  2",
            "│  └ a.jpg",
            "└ Documents/  1",
        ])
    }

    @Test func previewChangesWithDateFoldersAndRename() async throws {
        let model = try await makeModel()
        let before = model.previewLines
        model.options.dateFolders = true
        await model.planned()
        #expect(model.previewLines != before)
        #expect(model.previewLines.contains("│  └ 2024-05/a.jpg"))
        model.options.rename = true
        await model.planned()
        #expect(model.previewLines.contains("│  └ 2024-05/2024-05-12_Food_001.jpg"))
    }

    @Test func previewShowsAtMostThreeFolders() async throws {
        let (session, source) = try bigSession()
        let (model, _) = await makeModel(session, source: source)
        #expect(model.previewLines == [
            "Zalo export - sorted/",
            "├ C0/  343",
            "│  └ p0000.jpg",
            "├ C1/  343",
            "├ C2/  343",
            "└ …",
        ])
    }

    @Test func planRunsAgainWhenAnOptionChanges() async throws {
        let model = try await makeModel(notSure: true)
        #expect(model.plan?.entries.count == 3)
        model.options.notSureChoice = .leaveInSource
        await model.planned()
        #expect(model.plan?.entries.count == 2)
        #expect(model.title == "Sort 2 photos into 1 folder")
        model.options.notSureChoice = .notSureFolder
        await model.planned()
        #expect(model.plan?.folderCounts.map(\.folder) == ["Food", "Not sure"])
    }

    @Test func destinationIsSourceDisablesSort() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        model.options.destination = source
        await model.planned()
        #expect(model.planError == .destinationIsSource)
        #expect(!model.canSort)
        #expect(model.destinationNote == "The destination is the source folder. Choose another folder.")
        model.sort()
        #expect(model.state == .editing)
    }

    @Test func destinationInsidePhotoFolderDisablesSort() async throws {
        let (session, source) = try makeSession(files: ["a.jpg", "trip/b.jpg"])
        let (model, _) = await makeModel(session, source: source)
        model.options.destination = source.appending(path: "trip/out", directoryHint: .isDirectory)
        await model.planned()
        #expect(model.planError == .destinationInsideSource)
        #expect(!model.canSort)
        #expect(model.destinationNote == "Choose a folder outside the source folder.")
        // Final review I2: a folder inside the source with no photos is refused too.
        model.options.destination = source.appending(path: "Sorted", directoryHint: .isDirectory)
        await model.planned()
        #expect(model.planError == .destinationInsideSource)
        #expect(!model.canSort)
        model.options.destination = temp.url.appending(path: "Elsewhere", directoryHint: .isDirectory)
        await model.planned()
        #expect(model.planError == nil)
        #expect(model.destinationNote == nil)
        #expect(model.canSort)
    }

    /// Final review M5: the parent of the source as the destination, with a category named like the source.
    @Test func categoryFolderInsideSourceDisablesSort() async throws {
        var (session, source) = try makeSession()
        try #require(session.categories.count >= 1)
        session.categories[0].displayName = "Photos"
        let (model, _) = await makeModel(session, source: source)
        model.options.destination = source.deletingLastPathComponent()
        await model.planned()
        #expect(model.planError == .categoryFolderInsideSource)
        #expect(!model.canSort)
        #expect(model.destinationNote
            == "A category folder would land inside the source folder. Choose another destination.")
    }

    // MARK: - Sort

    /// Final review I4: a sort whose `sortedAt` cannot be saved says so in the summary.
    @Test func failedSaveAfterSortShowsInSummary() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        #expect(model.saveWarning == nil)
        try blockSessionSaves(environment.sessions, source: source)
        model.sort()
        await model.finished()
        #expect(model.state == .finished(copied: 3, moved: 0))
        let error = try #require(review.saveError)
        #expect(model.saveWarning == "Picnest could not save your changes: \(error.localizedDescription)")
    }

    @Test func copySortFinishesAndRecordsSort() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        model.sort()
        await model.finished()
        #expect(model.state == .finished(copied: 3, moved: 0))
        #expect(model.summaryText == "Copied 3 photos to “Photos - sorted”.")
        let destination = model.options.destination
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Food/a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "a.jpg").path))
        // The journal is in the session folder and is complete.
        let journal = environment.library.journal(for: source)
        #expect(try journal.lastIsComplete() == true)
        #expect(review.session.sortedAt != nil)
        #expect(try environment.sessions.load(source: source)?.sortedAt == review.session.sortedAt)
        #expect(environment.library.recent().first?.sortedAt == review.session.sortedAt)
    }

    @Test func moveAsksForConfirmationFirst() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        model.options.mode = .move
        await model.planned()
        model.sort()
        #expect(model.state == .confirmingMove)
        #expect(model.confirmMoveTitle == "Move 3 photos?")
        #expect(model.confirmMoveMessage == "Each original is deleted after its copy is checked.")
        model.cancelMove()
        #expect(model.state == .editing)
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "a.jpg").path))

        model.sort()
        model.confirmMove()
        await model.finished()
        #expect(model.state == .finished(copied: 0, moved: 3))
        #expect(model.summaryText == "Moved 3 photos to “Photos - sorted”.")
        #expect(!FileManager.default.fileExists(atPath: source.appending(path: "a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "d.jpg").path))
    }

    @Test func unfinishedLastSortShowsUndoText() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        try environment.library.journal(for: source).append(
            JournalEntry(op: .mkdir, source: nil, destination: temp.url.appending(path: "x").path, time: .now))
        model.sort()
        await model.finished()
        #expect(model.state == .failed("The last sort did not finish. Click Undo Last Sort first."))
        #expect(model.canUndoLastSort)
    }

    @Test func changedFileShowsRescanText() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        try Data(repeating: 9, count: 99).write(to: source.appending(path: "a.jpg"))
        model.sort()
        await model.finished()
        #expect(model.state == .failed("Some photos changed since the scan. Click Rescan, then sort again."))
        #expect(!model.canUndoLastSort)
    }

    @Test func errorTextForEachError() {
        let url = URL(filePath: "/tmp/x.jpg")
        #expect(SortMessages.text(for: SortError.unfinishedLastSort)
            == "The last sort did not finish. Click Undo Last Sort first.")
        #expect(SortMessages.text(for: SortError.changedSinceScan(["a.jpg"]))
            == "Some photos changed since the scan. Click Rescan, then sort again.")
        #expect(SortMessages.text(for: SortError.destinationExists([url]))
            == "Some files already exist in the destination. Choose another destination.")
        #expect(SortMessages.text(for: SortError.sizeMismatch(url))
            == "A copy did not match its original. The original was kept.")
        #expect(SortMessages.text(for: SortError.movedAfterUnfinishedSort(oldPath: NSHomeDirectory() + "/Pictures/Trip"))
            == "This folder moved after a sort that did not finish. Move it back to ~/Pictures/Trip, then click Undo Last Sort.")
        let other = CocoaError(.fileWriteNoPermission)
        #expect(SortMessages.text(for: other) == other.localizedDescription)
    }

    @Test func busyServiceWaitsAndRetriesOnce() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        let plan = try #require(model.plan)
        // Another run holds the service for a short time, then stops before its first file.
        let blocker = environment.sortService.run(
            plan, mode: .copy, journal: environment.library.journal(for: source),
            stop: { Thread.sleep(forTimeInterval: 0.3); return true })
        model.sort()
        await model.finished()
        #expect(model.state == .finished(copied: 3, moved: 0))
        withExtendedLifetime(blocker) {}
    }

    @Test func stopShowsStoppedSummaryWithUndo() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        model.sort()
        #expect(model.state == .running(done: 0, total: 3))
        model.stop()
        await model.finished()
        #expect(model.state == .stopped(done: 0, total: 3))
        #expect(model.summaryText == "Stopped after 0 of 3 photos.")
    }

    @Test func undoLastSortAfterFailureReturnsToEditing() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        let folder = temp.url.appending(path: "made", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try environment.library.journal(for: source).append(
            JournalEntry(op: .mkdir, source: nil, destination: folder.path, time: .now))
        model.sort()
        await model.finished()
        #expect(model.canUndoLastSort)
        // A stopped or failed sort that placed files records the sort time.
        review.markSorted(at: .now)
        model.undoLastSort()
        await model.finished()
        #expect(model.state == .editing)
        #expect(!model.canUndoLastSort)
        #expect(review.session.sortedAt == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        model.sort()
        await model.finished()
        #expect(model.state == .finished(copied: 3, moved: 0))
    }

    @Test func changedPlanReturnsToEditingWithoutRunning() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        let destination = model.options.destination
        #expect(model.title == "Sort 3 photos into 2 folders")
        review.dontMove(["a.jpg"])
        model.sort()
        await model.finished()
        // The plan on screen was for 3 photos: nothing runs, and the new plan shows.
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(model.state == .editing)
        #expect(model.title == "Sort 2 photos into 2 folders")
        #expect(model.notice == "The photos changed. Check the new plan, then sort again.")
        #expect(review.session.sortedAt == nil)

        model.sort()
        #expect(model.notice == nil)
        await model.finished()
        #expect(model.state == .finished(copied: 2, moved: 0))
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "Food/a.jpg").path))
    }

    @Test func changedPlanInMoveModeMovesNothing() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        model.options.mode = .move
        await model.planned()
        model.sort()
        review.dontMove(["a.jpg"])
        model.confirmMove()
        await model.finished()
        #expect(model.state == .editing)
        #expect(model.sortButtonTitle == "Move 2 Photos")
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "b.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: model.options.destination.path))
    }

    @Test func emptyPlanAtSortShowsNothingToSort() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        review.dontMove(["a.jpg", "b.jpg", "c.jpg"])
        model.sort()
        await model.finished()
        #expect(model.state == .editing)
        #expect(model.notice == "Nothing to sort.")
        #expect(!model.canSort)
    }

    @Test func sortIsDisabledWhilePlanning() async throws {
        let model = try await makeModel()
        #expect(model.canSort)
        model.options.dateFolders = true
        #expect(model.isPlanning)
        #expect(!model.canSort)
        model.sort()
        #expect(model.state == .editing)
        await model.planned()
        #expect(model.canSort)
    }

    @Test func showInFinderOnlyAfterFilesChanged() async throws {
        let (session, source) = try makeSession()
        let (model, _) = await makeModel(session, source: source)
        model.sort()
        model.stop()
        await model.finished()
        #expect(model.state == .stopped(done: 0, total: 3))
        #expect(!model.canShowInFinder)

        let (model2, _) = await makeModel(session, source: source)
        model2.sort()
        await model2.finished()
        #expect(model2.canShowInFinder)
    }

    // MARK: - After the sort (spec 9.1)

    @Test func doneAfterSortClosesTheSession() async throws {
        let (session, source) = try makeSession()
        var doneCount = 0
        let (model, _) = await makeModel(session, source: source) { doneCount += 1 }
        model.sort()
        await model.finished()
        model.done()
        #expect(doneCount == 1)
    }

    @Test func doneWithoutFilesReturnsToReview() async throws {
        let (session, source) = try makeSession()
        var doneCount = 0
        let (model, _) = await makeModel(session, source: source) { doneCount += 1 }
        model.sort()
        model.stop()
        await model.finished()
        #expect(model.state == .stopped(done: 0, total: 3))
        model.done()
        #expect(doneCount == 0)
    }

    @Test func reviewToolbarShowsUndoLastSortAfterSort() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        let reviewModel = makeReviewModel(review)
        #expect(!reviewModel.canUndoLastSort)
        model.sort()
        await model.finished()
        let copy = model.options.destination.appending(path: "Food/a.jpg")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(reviewModel.canUndoLastSort)

        await reviewModel.undoLastSort()
        #expect(reviewModel.undoSortMessage == nil)
        #expect(!reviewModel.canUndoLastSort)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: model.options.destination.path))
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "a.jpg").path))
        #expect(review.session.sortedAt == nil)
        #expect(try environment.sessions.load(source: source)?.sortedAt == nil)
        #expect(environment.library.recent().first?.sortedAt == nil)

        // The sheet opens again in the unsorted state, and a new sort can run.
        let (again, _) = await makeModel(review.session, source: source)
        #expect(!again.canUndoLastSort)
        again.sort()
        await again.finished()
        #expect(again.state == .finished(copied: 3, moved: 0))
    }

    private func makeReviewModel(_ review: ReviewService, app: AppModel? = nil,
                                 onRescan: @escaping () -> Void = {}) -> ReviewViewModel {
        ReviewViewModel(
            review: review, classify: environment.classifyService, thumbnails: environment.thumbnails,
            library: environment.library, app: app ?? AppModel(environment: environment), onRescan: onRescan)
    }

    @Test func doneAfterStopWithFilesKeepsReviewWithUndo() async throws {
        let files = (0..<400).map { String(format: "p%03d.jpg", $0) }
        let (session, source) = try makeSession(files: files)
        var doneCount = 0
        let (model, review) = await makeModel(session, source: source) { doneCount += 1 }
        let reviewModel = makeReviewModel(review)
        model.sort()
        // Stop after the first files are placed.
        for _ in 0..<2000 {
            if case .running(let done, _) = model.state, done > 0 { break }
            if case .finished = model.state { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        model.stop()
        await model.finished()
        guard case .stopped(let done, _) = model.state, done > 0 else {
            Issue.record("expected a stop after > 0 files, got \(model.state)"); return
        }
        #expect(review.session.sortedAt != nil)
        model.done()
        #expect(doneCount == 0)
        #expect(reviewModel.canUndoLastSort)

        await reviewModel.undoLastSort()
        #expect(reviewModel.undoSortMessage == nil)
        #expect(!reviewModel.canUndoLastSort)
        #expect(!FileManager.default.fileExists(atPath: model.options.destination.path))
        #expect(!environment.sortService.hasUnfinishedSort(journal: environment.library.journal(for: source)))
    }

    @Test func reviewWaitsWhileAnUndoRuns() async throws {
        let (session, source) = try makeSession()
        let (model, review) = await makeModel(session, source: source)
        let app = AppModel(environment: environment)
        var rescans = 0
        let reviewModel = makeReviewModel(review, app: app) { rescans += 1 }
        model.sort()
        await model.finished()
        #expect(app.beginUndo())
        #expect(reviewModel.isUndoingSort)
        #expect(!reviewModel.canSortOrRescan)
        reviewModel.rescan()
        #expect(rescans == 0)
        await reviewModel.undoLastSort()
        #expect(review.session.sortedAt != nil)
        app.endUndo()
        #expect(reviewModel.canSortOrRescan)
        reviewModel.rescan()
        #expect(rescans == 1)
    }

    // MARK: - View

    /// Lays out the sheet in the editing and summary states. Catches crashes in the view code.
    @Test func sortSheetLaysOut() async throws {
        let model = try await makeModel(notSure: true)
        let view = NSHostingView(rootView: SortSheet(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 470, height: 760)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0)
        model.sort()
        await model.finished()
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0)
    }

    // MARK: - Suggest hint (spec 3.5)

    /// `total` real files; the first `notSure` are Not sure, the others are Don't move.
    private func hintModel(total: Int, notSure: Int, onSuggest: @escaping () -> Void = {}) async throws -> SortViewModel {
        let files = (0..<total).map { "p\($0).jpg" }
        var (session, source) = try makeSession(files: files)
        for (i, name) in files.enumerated() { session.states[name] = i < notSure ? uncertain(documents) : .dontMove }
        let review = makeReview(session, source: source)
        let model = SortViewModel(
            review: review, sortService: environment.sortService, library: environment.library, locale: Self.locale,
            onDone: {}, onSuggest: onSuggest)
        await model.load()
        return model
    }

    @Test func suggestHintShowsAt20NotSureAndTenPercent() async throws {
        let model = try await hintModel(total: 200, notSure: 20)
        #expect(model.showSuggestHint)
        #expect(model.suggestHintText == "20 photos are not sure.")
    }

    @Test func suggestHintCountsImagesOnly() async throws {
        func model(images: Int) async throws -> SortViewModel {
            let names = (0..<images).map { "i\($0).jpg" } + (0..<1000).map { "v\($0).mov" }
            var (session, source) = try makeSession(files: names)
            session.scan.media = session.scan.media.map { file in
                var f = file
                if file.relativePath.hasSuffix(".mov") { f.kind = .video }
                return f
            }
            for (i, n) in names.enumerated() { session.states[n] = (i < 20) ? uncertain(documents) : .dontMove }
            let m = SortViewModel(
                review: makeReview(session, source: source), sortService: environment.sortService,
                library: environment.library, locale: Self.locale)
            await m.load()
            return m
        }
        #expect(try await model(images: 200).showSuggestHint)
        #expect(try await !model(images: 201).showSuggestHint)
    }

    @Test func suggestHintHidesAt19NotSure() async throws {
        #expect(try await !hintModel(total: 100, notSure: 19).showSuggestHint)
    }

    @Test func suggestHintHidesBelowTenPercent() async throws {
        // 24 of 250 is 9.6%.
        #expect(try await !hintModel(total: 250, notSure: 24).showSuggestHint)
    }

    @Test func suggestHintUsesGroupingSeparators() async throws {
        let model = try await hintModel(total: 1200, notSure: 1100)
        #expect(model.suggestHintText == "1,100 photos are not sure.")
    }

    @Test func suggestFromSortNavigates() async throws {
        var calls = 0
        let model = try await hintModel(total: 40, notSure: 20) { calls += 1 }
        model.suggestFromSort()
        #expect(calls == 1)
    }
}
