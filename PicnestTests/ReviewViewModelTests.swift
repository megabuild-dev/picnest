import AppKit
import Foundation
import PicnestCore
import SwiftUI
import Testing
@testable import Picnest

@MainActor
struct ReviewViewModelTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let food = PicnestCore.Category(id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 1)
    private let documents = PicnestCore.Category(
        id: UUID(), displayName: "Documents", emoji: "🧾", prompts: ["documents"], exampleIDs: [], order: 0)
    private let classify = ClassifyService(settings: .default)

    init() throws { temp = try TempDir() }

    private var environment: AppEnvironment {
        AppEnvironment(embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"),
                       defaults: suite.defaults)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func file(_ name: String, kind: MediaKind = .image, modified: Date? = nil) -> MediaFile {
        MediaFile(id: name, relativePath: name, kind: kind, size: 10, modified: modified ?? day(2020, 1, 1))
    }

    private func auto(_ c: PicnestCore.Category, _ percent: Int, uncertain: Bool = false) -> Assignment {
        Assignment(categoryID: c.id, score: 0.3, secondCategoryID: nil, secondScore: nil, percent: percent,
                   uncertain: uncertain)
    }

    /// 8 files, 1 of each kind of tile:
    /// a 91% Food, b 62% Food (uncertain), c manual Food, d held Not sure (Food 41%, or Documents 38%),
    /// e Don't move, f unreadable, g video, h 80% Documents with a modification-time date.
    private func makeSession(source: URL) -> Session {
        let s1: Float = 0.30
        let held = Assignment(
            categoryID: food.id, score: s1, secondCategoryID: documents.id,
            secondScore: s1 + ClassifySettings.default.temperature * Float(log(38.0 / 41.0)), percent: 41,
            uncertain: true)
        let media = [
            file("a.jpg", modified: day(2024, 1, 1)), file("b.jpg"), file("c.jpg"), file("d.jpg"),
            file("e.jpg"), file("f.jpg"), file("g.mov", kind: .video), file("h.jpg", modified: day(2019, 3, 3)),
        ]
        let states: [MediaID: PhotoState] = [
            "a.jpg": .auto(auto(food, 91)), "b.jpg": .auto(auto(food, 62, uncertain: true)),
            "c.jpg": .manual(food.id), "d.jpg": .heldNotSure(held), "e.jpg": .dontMove, "f.jpg": .unreadable,
            "h.jpg": .auto(auto(documents, 80)),
        ]
        let dates: [MediaID: PhotoDate] = [
            "a.jpg": PhotoDate(date: day(2024, 5, 12), source: .exif),
            "b.jpg": PhotoDate(date: day(2023, 11, 2), source: .fileNameTimestamp),
            "c.jpg": PhotoDate(date: day(2022, 7, 9), source: .exif),
            "d.jpg": PhotoDate(date: day(2021, 2, 1), source: .exif),
            "h.jpg": PhotoDate(date: day(2019, 3, 3), source: .modificationTime),
        ]
        return Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [food, documents],
            states: states, scan: ScanResult(media: media, dates: dates, skipped: [:]), sortedAt: nil)
    }

    private func makeModel(onRescan: @escaping () -> Void = {}) throws -> ReviewViewModel {
        try makeModelAndReview(onRescan: onRescan).model
    }

    private func makeModelAndReview(
        onRescan: @escaping () -> Void = {}, trashOps: FakeTrashFileOps = FakeTrashFileOps(), openURL: @escaping @MainActor (URL) -> Void = { _ in },
        revealURLs: @escaping @MainActor ([URL]) -> Void = { _ in }) throws -> (model: ReviewViewModel, review: ReviewService) {
        let source = try temp.folder("Photos")
        let review = ReviewService(
            session: makeSession(source: source), source: source, images: [:], prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")),
            trash: TrashService(fileOps: trashOps))
        let environment = self.environment
        let model = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, app: AppModel(environment: environment), onRescan: onRescan,
            openURL: openURL, revealURLs: revealURLs)
        return (model, review)
    }

    // MARK: - Save errors (final review I4)

    @Test func failedSaveShowsAlertTextAndTryAgainSaves() throws {
        let (model, review) = try makeModelAndReview()
        let sessions = SessionRepository(root: temp.url.appending(path: "Sessions"))
        let source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
        #expect(model.saveErrorMessage == nil)
        let blocker = try blockSessionSaves(sessions, source: source)
        review.markSorted(at: day(2026, 10, 21))
        let error = try #require(review.saveError)
        #expect(model.saveErrorMessage == "Picnest could not save your changes: \(error.localizedDescription)")

        model.dismissSaveError()
        #expect(model.saveErrorMessage == nil)
        review.retrySave()
        #expect(model.saveErrorMessage != nil)

        try FileManager.default.removeItem(at: blocker)
        model.retrySave()
        #expect(model.saveErrorMessage == nil)
        #expect(try sessions.load(source: source)?.sortedAt == day(2026, 10, 21))
    }

    // MARK: - Move to Trash (spec 3.3, 7.4)

    @Test func trashSelectionRemovesPhotosAndClearsSelection() async throws {
        let model = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.click("g.mov", modifiers: .command)
        await model.trashSelection()
        #expect(model.selection.isEmpty)
        #expect(model.trashMessage == nil)
        let items: [ReviewViewModel.SidebarItem] = [
            .all, .notSure, .changedByYou, .category(food.id), .category(documents.id), .dontMove, .videos, .unreadable,
        ]
        for item in items {
            model.selectedItem = item
            #expect(Set(model.visibleIDs).isDisjoint(with: ["a.jpg", "g.mov"]), "\(item)")
        }
        model.selectedItem = .notSure
        #expect(model.notSureGroups.flatMap(\.ids).allSatisfy { $0 != "a.jpg" })
        #expect(model.count(of: .all) == 6)
        #expect(model.count(of: .videos) == 0)
        #expect(model.count(of: .category(food.id)) == 1)  // c.jpg only
        #expect(model.previewURLs.allSatisfy { $0.lastPathComponent != "a.jpg" })
    }

    @Test func undoAfterTrashRestoresPhotos() async throws {
        let (model, _) = try makeModelAndReview()
        model.click("a.jpg", modifiers: [])
        await model.trashSelection()
        #expect(!model.visibleIDs.contains("a.jpg"))
        #expect(model.canUndo)
        model.undo()
        await model.settled()
        #expect(model.visibleIDs.contains("a.jpg"))
        #expect(model.trashMessage == nil)
        model.redo()
        await model.settled()
        #expect(!model.visibleIDs.contains("a.jpg"))
    }

    @Test func trashFailureShowsMessage() async throws {
        let model = try makeModelAndReview(trashOps: FakeTrashFileOps(failingNames: ["a.jpg"])).model
        model.click("a.jpg", modifiers: [])
        await model.trashSelection()
        #expect(model.trashMessage == "The photo could not be moved to the Trash: no permission.")
        #expect(model.visibleIDs.contains("a.jpg"))
    }

    @Test func severalTrashFailuresShowFirstMessageAndCount() async throws {
        let ops = FakeTrashFileOps(failingNames: ["a.jpg", "b.jpg", "c.jpg"])
        let model = try makeModelAndReview(trashOps: ops).model
        model.selectAll()
        await model.trashSelection()
        let message = try #require(model.trashMessage)
        #expect(message.hasPrefix("The photo could not be moved to the Trash: no permission"))
        #expect(message.hasSuffix("and 2 more)"))
        #expect(model.visibleIDs.count == 3)
    }

    @Test func putBackFailureShowsMessage() async throws {
        let ops = FakeTrashFileOps()
        let (model, _) = try makeModelAndReview(trashOps: ops)
        model.click("a.jpg", modifiers: [])
        await model.trashSelection()
        ops.forget(URL(filePath: "/FakeTrash/a.jpg"))  // The user emptied the Trash.
        model.undo()
        await model.settled()
        #expect(model.trashMessage == "The photo could not be put back: the file is not in the Trash any more.")
        #expect(model.trashAlertTitle == "Undo")
        #expect(!model.visibleIDs.contains("a.jpg"))
    }

    /// Final review M4: the Trash alert title names the action that failed.
    @Test func trashAlertTitleNamesTheAction() async throws {
        let ops = FakeTrashFileOps(failingNames: ["b.jpg"])
        let (model, _) = try makeModelAndReview(trashOps: ops)
        model.click("b.jpg", modifiers: [])
        await model.trashSelection()
        #expect(model.trashMessage != nil)
        #expect(model.trashAlertTitle == "Move to Trash")
        model.trashMessage = nil

        model.click("a.jpg", modifiers: [])
        await model.trashSelection()
        model.undo()
        await model.settled()
        #expect(model.trashMessage == nil)
        ops.setFailing(["a.jpg"])
        model.redo()
        await model.settled()
        #expect(model.trashMessage == "The photo could not be moved to the Trash: no permission.")
        #expect(model.trashAlertTitle == "Redo")
    }

    /// Final review M1: a ⌘Z or ⇧⌘Z that does nothing does not show the old Trash errors again.
    @Test func undoThatDoesNothingShowsNoOldError() async throws {
        let ops = FakeTrashFileOps()
        let (model, _) = try makeModelAndReview(trashOps: ops)
        model.click("a.jpg", modifiers: [])
        await model.trashSelection()
        ops.forget(URL(filePath: "/FakeTrash/a.jpg"))  // The user emptied the Trash.
        model.undo()
        await model.settled()
        #expect(model.trashMessage != nil)
        model.trashMessage = nil
        #expect(!model.canUndo && !model.canRedo)
        model.undo()
        await model.settled()
        #expect(model.trashMessage == nil)
        model.redo()
        await model.settled()
        #expect(model.trashMessage == nil)
    }

    /// Final review I1: while a Move to Trash runs, Sort, Rescan, and Undo Last Sort are off.
    @Test func sortRescanAndUndoSortAreOffWhileFilesMove() async throws {
        let ops = FakeTrashFileOps()
        var rescans = 0
        let (model, review) = try makeModelAndReview(onRescan: { rescans += 1 }, trashOps: ops)
        review.markSorted(at: day(2026, 10, 21))
        #expect(model.canSortOrRescan)
        ops.trashGate.hold()
        model.click("a.jpg", modifiers: [])
        let run = Task { await model.trashSelection() }
        try await ops.trashGate.untilWaiting()
        #expect(review.isMovingFiles)
        #expect(!model.canSortOrRescan)
        model.rescan()
        #expect(rescans == 0)
        await model.undoLastSort()
        #expect(review.session.sortedAt != nil)
        ops.trashGate.release()
        await run.value
        await review.settled()
        #expect(model.canSortOrRescan)
        model.rescan()
        #expect(rescans == 1)
    }

    // MARK: - visibleIDs

    @Test func visibleIDsForEachSidebarItem() throws {
        let model = try makeModel()
        func ids(_ item: ReviewViewModel.SidebarItem) -> Set<MediaID> {
            model.selectedItem = item
            return Set(model.visibleIDs)
        }
        #expect(ids(.all) == ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg", "f.jpg", "g.mov", "h.jpg"])
        #expect(ids(.notSure) == ["b.jpg", "d.jpg"])
        #expect(ids(.changedByYou) == ["c.jpg"])
        #expect(ids(.category(food.id)) == ["a.jpg", "c.jpg"])
        #expect(ids(.category(documents.id)) == ["h.jpg"])
        #expect(ids(.dontMove) == ["e.jpg"])
        #expect(ids(.videos) == ["g.mov"])
        #expect(ids(.unreadable) == ["f.jpg"])
    }

    @Test func sidebarCountsMatchVisibleIDs() throws {
        let model = try makeModel()
        let items: [ReviewViewModel.SidebarItem] = [
            .all, .notSure, .changedByYou, .category(food.id), .category(documents.id), .dontMove, .videos,
            .unreadable,
        ]
        for item in items {
            model.selectedItem = item
            #expect(model.count(of: item) == model.visibleIDs.count, "\(item)")
            #expect(model.count == model.visibleIDs.count)
        }
    }

    @Test func categoriesFollowOrder() throws {
        #expect(try makeModel().categories.map(\.displayName) == ["Documents", "Food"])
    }

    @Test func sidebarCountsHoldEveryItem() throws {
        let model = try makeModel()
        let counts = model.sidebarCounts
        #expect(counts[.all] == 8)
        #expect(counts[.notSure] == 2)
        #expect(counts[.category(food.id)] == 2)
        #expect(counts[.videos] == 1)
    }

    // MARK: - List cache

    @Test func selectionDoesNotRecomputeTheList() throws {
        let model = try makeModel()
        _ = model.visibleIDs
        let start = model.listComputations
        model.click("a.jpg", modifiers: [])
        _ = model.visibleIDs
        _ = model.previewURLs
        model.click("b.jpg", modifiers: .command)
        _ = model.visibleIDs
        model.click("e.jpg", modifiers: .shift)
        _ = model.visibleIDs
        model.selectAll()
        _ = model.visibleIDs
        model.clearSelection()
        _ = model.visibleIDs
        #expect(model.listComputations == start)
    }

    @Test func sortOrderItemAndSessionChangesRecomputeTheList() throws {
        let (model, review) = try makeModelAndReview()
        _ = model.visibleIDs
        var last = model.listComputations
        model.sortOrder = .name
        #expect(model.visibleIDs.first == "a.jpg")
        #expect(model.listComputations == last + 1)
        last = model.listComputations
        model.selectedItem = .dontMove
        #expect(model.visibleIDs == ["e.jpg"])
        #expect(model.listComputations == last + 1)
        last = model.listComputations
        review.dontMove(["a.jpg"])
        #expect(model.visibleIDs == ["a.jpg", "e.jpg"])
        #expect(model.listComputations == last + 1)
        _ = model.visibleIDs
        #expect(model.listComputations == last + 1)  // Cached again.
    }

    // MARK: - Thumbnail key

    @Test func loadPixelsIsZeroUntilTheTileHasAWidth() throws {
        let model = try makeModel()
        #expect(model.loadPixels(forTileWidth: 0) == 0)
        #expect(model.loadPixels(forTileWidth: 81) == 200)
        #expect(model.loadPixels(forTileWidth: 300) == 800)
    }

    // MARK: - Sort order

    @Test func lowestConfidenceIsDefaultAndPutsUnscoredLast() throws {
        let model = try makeModel()
        #expect(model.sortOrder == .lowestConfidence)
        #expect(model.visibleIDs == ["d.jpg", "b.jpg", "h.jpg", "a.jpg", "c.jpg", "e.jpg", "f.jpg", "g.mov"])
    }

    @Test func dateOrderIsOldestFirstWithModificationTimeForUndated() throws {
        let model = try makeModel()
        model.sortOrder = .date
        // e, f: no date entry, so their modification time (2020-01-01). g too.
        #expect(model.visibleIDs == ["h.jpg", "e.jpg", "f.jpg", "g.mov", "d.jpg", "c.jpg", "b.jpg", "a.jpg"])
    }

    @Test func nameOrder() throws {
        let model = try makeModel()
        model.sortOrder = .name
        #expect(model.visibleIDs == ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg", "f.jpg", "g.mov", "h.jpg"])
    }

    // MARK: - Tiles

    @Test func tileBadges() throws {
        let model = try makeModel()
        #expect(model.tile("a.jpg").badge == .percent(91, isUncertain: false))
        #expect(model.tile("b.jpg").badge == .percent(62, isUncertain: true))
        #expect(model.tile("c.jpg").badge == .you)
        #expect(model.tile("d.jpg").badge == .percent(41, isUncertain: true))
        #expect(model.tile("e.jpg").badge == nil)
        #expect(model.tile("f.jpg").badge == nil)
        #expect(model.tile("g.mov").badge == nil)
    }

    @Test func secondLineIsDateOrNoDateInCategoryViews() throws {
        let model = try makeModel()
        model.selectedItem = .category(food.id)
        #expect(model.tile("a.jpg").name == "a.jpg")
        #expect(model.tile("a.jpg").secondLine == "2024-05-12")
        #expect(model.tile("h.jpg").secondLine == "no date")
        #expect(model.tile("e.jpg").secondLine == "no date")
    }

    @Test func secondLineIsSecondGuessInNotSure() throws {
        let model = try makeModel()
        model.selectedItem = .notSure
        #expect(model.tile("d.jpg").secondLine == "or Documents 38%")
        #expect(model.tile("b.jpg").secondLine == "2023-11-02")  // No second guess: the date.
    }

    // MARK: - Toolbar

    @Test func titleShowsEmojiForCategories() throws {
        let model = try makeModel()
        #expect(model.title == "All photos")
        model.selectedItem = .category(food.id)
        #expect(model.title == "🍜 Food")
        model.selectedItem = .notSure
        #expect(model.title == "Not sure")
    }

    @Test func columnsDefaultToThreeAndStayInRange() throws {
        let model = try makeModel()
        #expect(model.columns == 3)
        model.columns = 12
        #expect(model.columns == 8)
        model.columns = 0
        #expect(model.columns == 2)
    }

    @Test func pathAbbreviatesHome() {
        #expect(ReviewViewModel.abbreviate("/Users/me/Pictures/Zalo export", home: "/Users/me")
            == "~/Pictures/Zalo export")
        #expect(ReviewViewModel.abbreviate("/Users/me", home: "/Users/me") == "~")
        #expect(ReviewViewModel.abbreviate("/Users/meg/Photos", home: "/Users/me") == "/Users/meg/Photos")
        #expect(ReviewViewModel.abbreviate("/Volumes/Disk/Photos", home: "/Users/me") == "/Volumes/Disk/Photos")
    }

    // MARK: - Selection and Quick Look

    @Test func previewOpensTheSelectedPhoto() throws {
        let model = try makeModel()
        model.selectedItem = .notSure
        model.openPreview()
        #expect(model.previewURL == nil)  // Nothing selected.
        model.click("d.jpg", modifiers: [])
        model.openPreview()
        #expect(model.previewURL?.lastPathComponent == "d.jpg")
        #expect(model.previewURLs.map(\.lastPathComponent) == ["d.jpg", "b.jpg"])
    }

    // MARK: - Context menu (spec 3.3)

    @Test func contextMenuSelectReplacesSelectionOnlyWhenOutside() throws {
        let model = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.click("b.jpg", modifiers: .command)
        model.contextMenuSelect("b.jpg")
        #expect(model.selection == ["a.jpg", "b.jpg"])
        model.contextMenuSelect("c.jpg")
        #expect(model.selection == ["c.jpg"])
        #expect(model.anchor == "c.jpg")
    }

    @Test func contextTargetsIsPure() throws {
        let model = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.click("c.jpg", modifiers: .command)
        #expect(model.contextTargets(for: "a.jpg").sorted() == ["a.jpg", "c.jpg"])
        #expect(model.contextTargets(for: "b.jpg") == ["b.jpg"])
        #expect(model.selection == ["a.jpg", "c.jpg"])
        #expect(model.anchor == "c.jpg")
    }

    @Test func canAcceptForUnselectedNotSurePhoto() throws {
        let model = try makeModel()
        model.click("c.jpg", modifiers: [])
        #expect(model.canAccept(model.contextTargets(for: "d.jpg")))
        #expect(!model.canAccept(model.contextTargets(for: "c.jpg")))
        #expect(model.selection == ["c.jpg"])
    }

    @Test func contextOpenActsOnTheClickedPhoto() throws {
        var opened: [URL] = []
        let model = try makeModelAndReview(openURL: { opened.append($0) }).model
        model.click("a.jpg", modifiers: [])
        model.click("c.jpg", modifiers: .command)
        model.click("a.jpg", modifiers: [.command])
        model.click("a.jpg", modifiers: [.command])  // anchor a, selection a + c
        model.contextMenuSelect("c.jpg")
        model.openInDefaultApp("c.jpg")
        #expect(opened.map(\.lastPathComponent) == ["c.jpg"])
        #expect(model.anchor == "a.jpg")
    }

    @Test func openInDefaultAppUsesTheAnchor() throws {
        var opened: [URL] = []
        let model = try makeModelAndReview(openURL: { opened.append($0) }).model
        model.openInDefaultApp()
        #expect(opened.isEmpty)  // Nothing selected.
        model.click("a.jpg", modifiers: [])
        model.click("c.jpg", modifiers: .command)
        model.openInDefaultApp()
        #expect(opened.map(\.lastPathComponent) == ["c.jpg"])
    }

    @Test func showInFinderRevealsTheSelection() throws {
        var revealed: [[URL]] = []
        let model = try makeModelAndReview(revealURLs: { revealed.append($0) }).model
        model.showInFinder()
        #expect(revealed.isEmpty)
        model.click("c.jpg", modifiers: [])
        model.click("a.jpg", modifiers: .command)
        model.showInFinder()
        try #require(revealed.count == 1)
        #expect(Set(revealed[0].map(\.lastPathComponent)) == ["a.jpg", "c.jpg"])
    }

    // MARK: - Multi-selection

    @Test func plainClickSelectsOnlyThatPhoto() throws {
        let model = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.click("b.jpg", modifiers: [])
        #expect(model.selection == ["b.jpg"])
        #expect(model.anchor == "b.jpg")
    }

    @Test func commandClickTogglesAndMovesTheAnchor() throws {
        let model = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.click("c.jpg", modifiers: .command)
        #expect(model.selection == ["a.jpg", "c.jpg"])
        #expect(model.anchor == "c.jpg")
        model.click("a.jpg", modifiers: .command)  // Deselects a; the anchor stays on c, still selected.
        #expect(model.selection == ["c.jpg"])
        #expect(model.anchor == "c.jpg")
        model.click("c.jpg", modifiers: .command)  // Deselects the anchor: no anchor is left on it.
        #expect(model.selection.isEmpty)
        #expect(model.anchor == nil)
    }

    @Test func shiftClickSelectsTheRangeInVisibleOrder() throws {
        let model = try makeModel()
        // Lowest confidence: d, b, h, a, c, e, f, g.
        model.click("h.jpg", modifiers: [])
        model.click("e.jpg", modifiers: .shift)
        #expect(model.selection == ["h.jpg", "a.jpg", "c.jpg", "e.jpg"])
        #expect(model.anchor == "h.jpg")  // The anchor stays.
        model.click("b.jpg", modifiers: .shift)  // Backwards from the anchor; adds to the selection.
        #expect(model.selection == ["b.jpg", "h.jpg", "a.jpg", "c.jpg", "e.jpg"])
    }

    @Test func shiftClickWithoutAnchorSelectsOnePhoto() throws {
        let model = try makeModel()
        model.click("c.jpg", modifiers: .shift)
        #expect(model.selection == ["c.jpg"])
        #expect(model.anchor == "c.jpg")
    }

    @Test func selectAllSelectsTheVisiblePhotos() throws {
        let model = try makeModel()
        model.selectedItem = .notSure
        model.selectAll()
        #expect(model.selection == ["b.jpg", "d.jpg"])
    }

    @Test func changingTheSidebarItemClearsTheSelection() throws {
        let model = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.selectedItem = .notSure
        #expect(model.selection.isEmpty)
        #expect(model.anchor == nil)
    }

    @Test func photosThatLeaveTheListLeaveTheSelection() throws {
        let (model, review) = try makeModelAndReview()
        model.selectedItem = .notSure
        model.selectAll()
        review.dontMove(["b.jpg"])
        _ = model.visibleIDs
        #expect(model.selection == ["d.jpg"])
    }

    @Test func dragCarriesTheSelectionOrJustTheTile() throws {
        let model = try makeModel()
        model.click("h.jpg", modifiers: [])
        model.click("d.jpg", modifiers: .command)
        #expect(model.dragIDs(for: "h.jpg") == ["d.jpg", "h.jpg"])  // Visible order.
        #expect(model.dragIDs(for: "a.jpg") == ["a.jpg"])
    }

    // MARK: - Actions

    @Test func moveSelectionClearsItAndPhotosLeaveNotSure() throws {
        let (model, review) = try makeModelAndReview()
        model.selectedItem = .notSure
        model.selectAll()
        model.moveSelection(to: documents.id)
        #expect(model.selection.isEmpty)
        #expect(model.visibleIDs.isEmpty)
        #expect(review.session.states["b.jpg"] == .manual(documents.id))
        #expect(model.canUndo)
        model.undo()
        #expect(model.visibleIDs == ["d.jpg", "b.jpg"])
        #expect(model.canRedo)
        model.redo()
        #expect(model.visibleIDs.isEmpty)
    }

    @Test func numberKeysMoveToTheCategoryInSidebarOrder() throws {
        let (model, review) = try makeModelAndReview()
        #expect(model.moveSelection(toKey: 2) == false)  // No selection.
        model.click("h.jpg", modifiers: [])
        #expect(model.moveSelection(toKey: 3) == false)  // Only 2 categories.
        #expect(model.moveSelection(toKey: 0) == false)
        #expect(model.selection == ["h.jpg"])
        #expect(model.moveSelection(toKey: 2))  // Documents is 1st, Food is 2nd.
        #expect(review.session.states["h.jpg"] == .manual(food.id))
        #expect(model.selection.isEmpty)
    }

    @Test func canAcceptSelectionNeedsANotSurePhoto() throws {
        let model = try makeModel()
        #expect(!model.canAcceptSelection)
        model.click("a.jpg", modifiers: [])
        model.click("c.jpg", modifiers: .command)
        #expect(!model.canAcceptSelection)
        model.click("d.jpg", modifiers: .command)
        #expect(model.canAcceptSelection)
    }

    @Test func acceptSelectionPicksBestGuessesAndClearsIt() throws {
        let (model, review) = try makeModelAndReview()
        model.click("d.jpg", modifiers: [])
        model.click("a.jpg", modifiers: .command)
        model.acceptSelection()
        #expect(model.selection.isEmpty)
        #expect(review.session.states["d.jpg"] == .manual(food.id))
        #expect(review.session.states["a.jpg"] == .auto(auto(food, 91)))  // Not uncertain: no change.
    }

    @Test func dontMoveSelectionClearsIt() throws {
        let (model, review) = try makeModelAndReview()
        model.click("a.jpg", modifiers: [])
        model.dontMoveSelection()
        #expect(model.selection.isEmpty)
        #expect(review.session.states["a.jpg"] == .dontMove)
        model.undo()
        #expect(review.session.states["a.jpg"] == .auto(auto(food, 91)))
    }

    @Test func dropMovesThePhotos() throws {
        let (model, review) = try makeModelAndReview()
        model.click("a.jpg", modifiers: [])
        #expect(model.drop(["a.jpg", "h.jpg"], on: food.id))
        #expect(review.session.states["h.jpg"] == .manual(food.id))
        #expect(model.selection.isEmpty)
        #expect(!model.drop([], on: food.id))
    }

    // MARK: - Category edits

    @Test func deleteConfirmationTextAndLastCategory() throws {
        let (model, review) = try makeModelAndReview()
        #expect(model.deleteConfirmation(for: food.id) == "Delete Food? Its 2 photos go to Not sure.")
        #expect(model.canDeleteCategory)
        model.selectedItem = .category(food.id)
        model.deleteCategory(food.id)
        #expect(review.session.categories.map(\.id) == [documents.id])
        #expect(model.selectedItem == .notSure)  // The deleted category's list is gone.
        #expect(!model.canDeleteCategory)
        model.deleteCategory(documents.id)
        #expect(review.session.categories.count == 1)
    }

    @Test func mergeMovesTheViewToTheTarget() throws {
        let (model, review) = try makeModelAndReview()
        model.selectedItem = .category(food.id)
        model.merge(food.id, into: documents.id)
        #expect(review.session.states["c.jpg"] == .manual(documents.id))
        #expect(model.selectedItem == .category(documents.id))
        #expect(model.mergeTargets(for: documents.id).isEmpty)
    }

    @Test func renameTrimsAndIgnoresEmptyNames() throws {
        let model = try makeModel()
        model.renameCategory(food.id, to: "  ")
        #expect(model.categories.last?.displayName == "Food")
        model.renameCategory(food.id, to: " Meals ")
        #expect(model.categories.last?.displayName == "Meals")
    }

    @Test func emojiValidation() {
        for good in ["🍜", "👍🏽", "🇻🇳", "☺️", "1️⃣", "👨‍👩‍👧"] {
            #expect(ReviewViewModel.isSingleEmoji(good), "\(good)")
        }
        for bad in ["", "a", "1", "🍜🍜", "ab", "☺", " "] {
            #expect(!ReviewViewModel.isSingleEmoji(bad), "\(bad)")
        }
    }

    @Test func setEmojiIgnoresInvalidInput() throws {
        let model = try makeModel()
        #expect(!model.setEmoji(food.id, "x"))
        #expect(model.categories.last?.emoji == "🍜")
        #expect(model.setEmoji(food.id, " 🍕 "))
        #expect(model.categories.last?.emoji == "🍕")
    }

    @Test func reorderFollowsTheDrag() throws {
        let model = try makeModel()
        model.moveCategories(from: IndexSet(integer: 1), to: 0)
        #expect(model.categories.map(\.displayName) == ["Food", "Documents"])
    }

    @Test func newCategoryFromMoveToMovesTheSelection() throws {
        let (model, review) = try makeModelAndReview()
        model.selectedItem = .notSure
        model.selectAll()
        model.requestNewCategory(movingSelection: true)
        #expect(model.isNamingNewCategory)
        #expect(model.newCategoryMovesPhotos)
        #expect(model.createNewCategory(name: " Pets "))
        #expect(!model.isNamingNewCategory)
        #expect(!model.newCategoryMovesPhotos)
        let pets = try #require(model.categories.last)
        #expect(pets.displayName == "Pets")
        #expect(pets.emoji == "📁")
        #expect(review.session.states["b.jpg"] == .manual(pets.id))
        #expect(review.session.states["d.jpg"] == .manual(pets.id))
        #expect(model.selection.isEmpty)
    }

    /// SwiftUI sets `isPresented` to false before it runs the Create action. The move must still happen.
    @Test func newCategoryMovesThePhotosAfterTheAlertCloses() throws {
        let (model, review) = try makeModelAndReview()
        model.click("b.jpg", modifiers: [])
        model.requestNewCategory(movingSelection: true)
        model.isNamingNewCategory = false
        #expect(model.createNewCategory(name: "Pets"))
        let pets = try #require(model.categories.last)
        #expect(review.session.states["b.jpg"] == .manual(pets.id))
        #expect(model.selection.isEmpty)
    }

    @Test func emptyNewCategoryNameCreatesNothing() throws {
        let model = try makeModel()
        model.click("b.jpg", modifiers: [])
        model.requestNewCategory(movingSelection: true)
        model.isNamingNewCategory = false
        #expect(!model.createNewCategory(name: "   "))
        #expect(model.categories.count == 2)
        #expect(!model.newCategoryMovesPhotos)
        #expect(model.selection == ["b.jpg"])
    }

    @Test func cancelNewCategoryForgetsTheMove() throws {
        let model = try makeModel()
        model.click("b.jpg", modifiers: [])
        model.requestNewCategory(movingSelection: true)
        model.isNamingNewCategory = false
        model.cancelNewCategory()
        #expect(!model.newCategoryMovesPhotos)
        #expect(model.categories.count == 2)
    }

    @Test func newCategoryFromSidebarMovesNothing() throws {
        let (model, review) = try makeModelAndReview()
        model.click("b.jpg", modifiers: [])
        model.requestNewCategory(movingSelection: false)
        #expect(model.createNewCategory(name: "Pets"))
        #expect(model.categories.count == 3)
        #expect(review.session.states["b.jpg"] == .auto(auto(food, 62, uncertain: true)))
        #expect(model.selection == ["b.jpg"])
    }

    // MARK: - Edit menu

    @Test func undoInATextFieldIsTextUndo() {
        #expect(UndoRouting.route(firstResponderIsText: true, reviewCanAct: false) == .text)
        #expect(UndoRouting.route(firstResponderIsText: true, reviewCanAct: true) == .text)
        #expect(UndoRouting.route(firstResponderIsText: false, reviewCanAct: false) == .nothing)
        #expect(UndoRouting.route(firstResponderIsText: false, reviewCanAct: true) == .review)
    }

    // MARK: - Rescan

    @Test func rescanCallsTheAppModel() throws {
        var calls = 0
        let model = try makeModel { calls += 1 }
        model.rescan()
        #expect(calls == 1)
    }

    @Test func appRescanDropsReviewAndScansInRescanMode() async throws {
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "AppSessions"), defaults: suite.defaults)
        let app = AppModel(environment: environment)
        let folder = try temp.folder("Saved")
        try Data([0]).write(to: folder.appending(path: "a.jpg"))
        let session = Session(
            sourcePath: folder.path(percentEncoded: false), candidateList: .everyday, categories: [food],
            states: ["a.jpg": .manual(food.id)], scan: ScanResult(media: [file("a.jpg")], dates: [:], skipped: [:]),
            sortedAt: nil)
        try environment.sessions.save(session)
        app.open(folder)
        await app.settled()
        guard case .review = app.screen else { Issue.record("Expected review, got \(app.screen)"); return }

        app.rescan()
        await app.settled()
        guard case .scanning(let url, let old?) = app.screen else {
            Issue.record("Expected scanning in rescan mode, got \(app.screen)"); return
        }
        #expect(url.lastPathComponent == "Saved")
        #expect(old.states["a.jpg"] == .manual(food.id))
    }

    // MARK: - Suggest sheet after a scan (spec 3.7)

    /// `notSure` uncertain Food images and `30 - notSure` certain ones.
    private func makeAfterScanModel(notSure: Int, afterScan: Bool) throws -> ReviewViewModel {
        let source = try temp.folder("Photos")
        let names = (0..<30).map { "p\($0).jpg" }
        var states: [MediaID: PhotoState] = [:]
        for (i, name) in names.enumerated() { states[name] = .auto(auto(food, i < notSure ? 40 : 90, uncertain: i < notSure)) }
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [food, documents],
            states: states, scan: ScanResult(media: names.map { file($0) }, dates: [:], skipped: [:]), sortedAt: nil)
        let review = ReviewService(
            session: session, source: source, images: [:], prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")))
        let environment = self.environment
        return ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, app: AppModel(environment: environment), afterScan: afterScan, onRescan: {})
    }

    @Test func suggestOpensOnceAfterScanWithManyNotSure() throws {
        let model = try makeAfterScanModel(notSure: 25, afterScan: true)
        model.suggestAfterScanIfNeeded()
        #expect(model.suggest != nil)
        #expect(model.selectedItem == .notSure)
        model.closeSuggest()
        model.suggestAfterScanIfNeeded()
        #expect(model.suggest == nil)
    }

    @Test func suggestDoesNotOpenOnReopen() throws {
        let model = try makeAfterScanModel(notSure: 25, afterScan: false)
        model.suggestAfterScanIfNeeded()
        #expect(model.suggest == nil)
        #expect(model.selectedItem == .all)
    }

    @Test func suggestDoesNotOpenWithFewNotSure() throws {
        let model = try makeAfterScanModel(notSure: 19, afterScan: true)
        model.suggestAfterScanIfNeeded()
        #expect(model.suggest == nil)
    }

    // MARK: - Start Over… (spec 3.3)

    @Test func startOverMessageAddsSortedSentence() throws {
        let (model, review) = try makeModelAndReview()
        let text = "The app scans the folder again and proposes new categories. Your categories and picks are lost."
        #expect(model.startOverMessage == text)
        review.markSorted(at: day(2026, 10, 21))
        #expect(model.startOverMessage == text + " The last sort can no longer be undone.")
    }

    @Test func requestStartOverAsksFirst() throws {
        let model = try makeModel()
        #expect(model.canStartOver)
        model.requestStartOver()
        #expect(model.isConfirmingStartOver)
    }

    /// An app on the review of a saved folder `Saved` (1 photo), and a view model of that review.
    private func appOnReview() async throws -> (app: AppModel, model: ReviewViewModel, source: URL, environment: AppEnvironment) {
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "AppSessions"), defaults: suite.defaults)
        let app = AppModel(environment: environment)
        let folder = try temp.folder("Saved")
        try Data([0]).write(to: folder.appending(path: "a.jpg"))
        try environment.sessions.save(Session(
            sourcePath: folder.path(percentEncoded: false), candidateList: .everyday, categories: [food],
            states: ["a.jpg": .manual(food.id)], scan: ScanResult(media: [file("a.jpg")], dates: [:], skipped: [:]),
            sortedAt: nil))
        app.open(folder)
        await app.settled()
        enum Failure: Error { case notInReview }
        guard case .review(let review, _) = app.screen else { throw Failure.notInReview }
        let model = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, app: app, onRescan: {})
        return (app, model, folder, environment)
    }

    @Test func startOverAfterUnfinishedSortShowsMessage() async throws {
        let (app, model, source, environment) = try await appOnReview()
        try environment.library.journal(for: source).append(
            JournalEntry(op: .mkdir, source: nil, destination: temp.url.appending(path: "x").path, time: .now))

        await model.startOver()
        #expect(model.startOverErrorMessage == SortMessages.text(for: SortError.unfinishedLastSort))
        guard case .review = app.screen else { Issue.record("Expected review, got \(app.screen)"); return }
        #expect(try environment.sessions.load(source: source) != nil)
    }

    @Test func startOverFromTheReviewRunsFirstScan() async throws {
        let (app, model, _, _) = try await appOnReview()
        await model.startOver()
        #expect(model.startOverErrorMessage == nil)
        guard case .scanning(_, nil) = app.screen else { Issue.record("Expected a first scan, got \(app.screen)"); return }
    }

    @Test func startOverIsOffWhileFilesMove() async throws {
        let ops = FakeTrashFileOps()
        let (model, review) = try makeModelAndReview(trashOps: ops)
        #expect(model.canStartOver)
        ops.trashGate.hold()
        model.click("a.jpg", modifiers: [])
        let run = Task { await model.trashSelection() }
        try await ops.trashGate.untilWaiting()
        #expect(!model.canStartOver)
        model.requestStartOver()
        #expect(!model.isConfirmingStartOver)
        ops.trashGate.release()
        await run.value
        await review.settled()
        #expect(model.canStartOver)
    }

    @Test func startOverDoesNothingWhileAnUndoRuns() async throws {
        let (app, model, source, environment) = try await appOnReview()
        #expect(app.beginUndo())
        #expect(!model.canStartOver)
        await model.startOver()
        guard case .review = app.screen else { Issue.record("Expected review, got \(app.screen)"); return }
        #expect(try environment.sessions.load(source: source) != nil)
        app.endUndo()
    }

    // MARK: - Not sure groups

    private let pets = PicnestCore.Category(id: UUID(), displayName: "Pets", emoji: "🐶", prompts: ["pets"], exampleIDs: [], order: 2)

    /// Not sure: Food n1 (50%), n2 (40%), n3 (45%); Documents n4 (30%), n5 (35%); Pets n6 (20%). Plus 1 certain photo.
    private func makeGroupedModel() throws -> (model: ReviewViewModel, review: ReviewService) {
        let source = try temp.folder("Photos")
        let spec: [(String, PicnestCore.Category, Int)] = [
            ("n1.jpg", food, 50), ("n2.jpg", food, 40), ("n3.jpg", food, 45),
            ("n4.jpg", documents, 30), ("n5.jpg", documents, 35), ("n6.jpg", pets, 20),
        ]
        var states: [MediaID: PhotoState] = ["ok.jpg": .auto(auto(food, 90))]
        for (name, category, percent) in spec { states[name] = .auto(auto(category, percent, uncertain: true)) }
        let media = (spec.map(\.0) + ["ok.jpg"]).map { file($0) }
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday,
            categories: [food, documents, pets], states: states,
            scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil)
        let review = ReviewService(
            session: session, source: source, images: [:], prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")))
        let environment = self.environment
        let model = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, app: AppModel(environment: environment), onRescan: {})
        model.selectedItem = .notSure
        return (model, review)
    }

    @Test func notSureGroupsAreLargestFirstAndFollowSortOrder() throws {
        let (model, _) = try makeGroupedModel()
        #expect(model.notSureGroups.map(\.categoryName) == ["Food", "Documents", "Pets"])
        try #require(model.notSureGroups.map(\.ids) == [["n2.jpg", "n3.jpg", "n1.jpg"], ["n4.jpg", "n5.jpg"], ["n6.jpg"]])
        model.sortOrder = .name
        #expect(model.notSureGroups[0].ids == ["n1.jpg", "n2.jpg", "n3.jpg"])
        #expect(model.visibleIDs == ["n1.jpg", "n2.jpg", "n3.jpg", "n4.jpg", "n5.jpg", "n6.jpg"])
    }

    @Test func acceptGroupEmptiesItAndRaisesChangedByYou() throws {
        let (model, _) = try makeGroupedModel()
        let before = model.count(of: .changedByYou)
        model.acceptGroup(at: 0)
        #expect(model.notSureGroups.map(\.categoryName) == ["Documents", "Pets"])
        #expect(model.count(of: .changedByYou) == before + 3)
        #expect(model.count(of: .notSure) == 3)
        model.acceptGroup(at: 9)  // Out of range: nothing happens.
        #expect(model.count(of: .notSure) == 3)
    }

    @Test func acceptAllEmptiesNotSureAndUndoRestoresGroups() throws {
        let (model, _) = try makeGroupedModel()
        let groups = model.notSureGroups
        model.acceptAll()
        #expect(model.notSureGroups.isEmpty)
        #expect(model.count(of: .notSure) == 0)
        #expect(model.visibleIDs.isEmpty)
        model.undo()
        #expect(model.notSureGroups == groups)
    }

    @Test func selectGroupReplacesSelection() throws {
        let (model, _) = try makeGroupedModel()
        model.click("n6.jpg", modifiers: [])
        model.selectGroup(at: 1)
        #expect(model.selection == ["n4.jpg", "n5.jpg"])
        #expect(model.anchor == "n4.jpg")
    }

    @Test func selectionDoesNotRecomputeGroups() throws {
        let (model, _) = try makeGroupedModel()
        _ = model.notSureGroups
        _ = model.visibleIDs
        let groups = model.groupComputations, lists = model.listComputations
        model.click("n1.jpg", modifiers: [])
        model.selectGroup(at: 0)
        model.selectAll()
        model.clearSelection()
        _ = model.notSureGroups
        _ = model.visibleIDs
        #expect(model.groupComputations == groups)
        #expect(model.listComputations == lists)
    }

    @Test func shiftClickRangeCrossesGroups() throws {
        let (model, _) = try makeGroupedModel()
        // Flattened order: n2 n3 n1 | n4 n5 | n6.
        model.click("n1.jpg", modifiers: [])
        model.click("n5.jpg", modifiers: .shift)
        #expect(model.selection == ["n1.jpg", "n4.jpg", "n5.jpg"])
    }

    // MARK: - View

    /// Lays out the whole Review screen off screen with every tile kind. Catches crashes in the view code.
    @Test func reviewViewLaysOut() throws {
        let source = try temp.folder("Photos")
        let review = ReviewService(
            session: makeSession(source: source), source: source, images: [:], prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")))
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
        let view = NSHostingView(rootView: ReviewView(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            sortService: environment.sortService, library: environment.library,
            app: AppModel(environment: environment)))
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0)
    }

    @Test func notSureViewLaysOut() throws {
        let (model, _) = try makeGroupedModel()
        let view = NSHostingView(rootView: NotSureView(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0)
        model.acceptAll()
        view.layoutSubtreeIfNeeded()
    }

    // MARK: - Suggest Categories (spec 3.4)

    @Test func canSuggestNeedsSevenNotSurePhotos() throws {
        func model(notSure: Int) throws -> ReviewViewModel {
            let source = try temp.folder("Photos\(notSure)")
            let ids = (0..<notSure).map { "n\($0).jpg" }
            let held = Assignment(categoryID: food.id, score: 0.3, secondCategoryID: nil, secondScore: nil, percent: 40,
                                  uncertain: true)
            let session = Session(
                sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [food],
                states: Dictionary(uniqueKeysWithValues: ids.map { ($0, PhotoState.heldNotSure(held)) }),
                scan: ScanResult(media: ids.map { file($0) }, dates: [:], skipped: [:]), sortedAt: nil)
            let review = ReviewService(
                session: session, source: source, images: [:], prompts: [:], classify: classify,
                sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
                embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")))
            return ReviewViewModel(
                review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
                library: environment.library, app: AppModel(environment: environment), onRescan: {})
        }
        #expect(try !model(notSure: 6).canSuggest)
        let seven = try model(notSure: 7)
        #expect(seven.canSuggest)
        #expect(seven.suggest == nil)
        seven.openSuggest()
        #expect(seven.selectedItem == .notSure)
        #expect(seven.suggest != nil)
        seven.closeSuggest()
        #expect(seven.suggest == nil)
    }
}
