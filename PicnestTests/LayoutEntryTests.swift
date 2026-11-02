import AppKit
import Foundation
import PicnestCore
import Testing
@testable import Picnest

@MainActor
struct LayoutEntryTests {
    private let fx: ReviewFixture

    init() throws { fx = try ReviewFixture() }

    private func session(
        trashed: [TrashedPhoto] = [], collections: [PhotoCollection] = [], draft: LayoutDocument? = nil
    ) -> (URL) -> Session {
        { [fx] source in
            var session = fx.makeSession(source: source)
            session.trashed = trashed
            session.collections = collections
            session.layoutDraft = draft
            return session
        }
    }

    private func trash(_ id: MediaID) -> TrashedPhoto {
        TrashedPhoto(mediaID: id, trashPath: "/FakeTrash/\(id)", time: fx.day(2026, 1, 1))
    }

    private func makeModel(
        trashOps: FakeTrashFileOps = FakeTrashFileOps(), session: ((URL) -> Session)? = nil
    ) throws -> (model: ReviewViewModel, review: ReviewService) {
        try fx.makeModelAndReview(trashOps: trashOps, session: session)
    }

    private func photos(_ model: ReviewViewModel) -> [MediaID]? { model.layoutEditor?.document.photoIDs }

    // MARK: - Which photos open

    @Test func testLayoutFromSelectionUsesGridOrder() throws {
        let (model, _) = try makeModel()
        model.sortOrder = .name
        model.click("c.jpg", modifiers: [])
        model.click("a.jpg", modifiers: .command)
        model.click("f.jpg", modifiers: .command)  // unreadable
        model.click("g.mov", modifiers: .command)  // a video
        #expect(model.canCreateLayout(from: .selection))
        model.requestLayout(from: .selection)
        #expect(photos(model) == ["a.jpg", "c.jpg"])
        #expect(model.layoutEditor?.document.title == "")
        #expect(model.askingToContinueLayout == nil)
    }

    @Test func testLayoutFromCategoryLeavesOutVideoAndTrashed() throws {
        let food = fx.food
        let (model, _) = try makeModel(session: session(trashed: [trash("c.jpg")]))
        model.sortOrder = .name
        #expect(model.canCreateLayout(from: .category(food.id)))
        model.requestLayout(from: .category(food.id))
        #expect(photos(model) == ["a.jpg"])
        #expect(model.layoutEditor?.document.title == "Food")
        let all = model.layoutEditor?.sourceOptions.first { $0.id == "all" }?.photos.map(\.id) ?? []
        #expect(!all.contains("g.mov") && !all.contains("c.jpg") && !all.contains("f.jpg"))
    }

    @Test func testLayoutFromCollectionUsesMemberOrder() throws {
        let collection = PhotoCollection(name: "Trip", memberIDs: ["h.jpg", "g.mov", "b.jpg", "a.jpg", "c.jpg"], order: 0)
        let (model, _) = try makeModel(session: session(trashed: [trash("b.jpg")], collections: [collection]))
        model.requestLayout(from: .collection(collection.id))
        #expect(photos(model) == ["h.jpg", "a.jpg", "c.jpg"])
        #expect(model.layoutEditor?.document.title == "Trip")
    }

    @Test func testCreateLayoutNeedsAPhoto() throws {
        let (model, _) = try makeModel()
        #expect(!model.canCreateLayout(from: .selection))
        model.requestLayout(from: .selection)
        #expect(model.layoutEditor == nil)
        let empty = PhotoCollection(name: "Empty", order: 0)
        let (other, _) = try makeModel(session: session(collections: [empty]))
        #expect(!other.canCreateLayout(from: .collection(empty.id)))
    }

    @Test func testCreateLayoutIsOffWhileFilesMove() async throws {
        let ops = FakeTrashFileOps()
        let (model, review) = try makeModel(trashOps: ops)
        let food = fx.food.id
        #expect(model.canCreateLayout(from: .category(food)))
        ops.trashGate.hold()
        model.click("b.jpg", modifiers: [])
        let run = Task { await model.trashSelection() }
        try await ops.trashGate.untilWaiting()
        #expect(!model.canCreateLayout(from: .category(food)))
        model.requestLayout(from: .category(food))
        #expect(model.layoutEditor == nil && model.askingToContinueLayout == nil)
        ops.trashGate.release()
        await run.value
        await review.settled()
        #expect(model.canCreateLayout(from: .category(food)))
    }

    // MARK: - The draft

    @Test func testDraftAsksToContinue() throws {
        let draft = LayoutDocument.new(photos: ["h.jpg", "a.jpg"], title: "Old")
        let (model, _) = try makeModel(session: session(draft: draft))
        model.click("c.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        #expect(model.askingToContinueLayout == .selection)
        #expect(model.layoutEditor == nil)
        model.continueLayout()
        #expect(model.askingToContinueLayout == nil)
        #expect(model.layoutEditor?.document == draft)
    }

    @Test func testAnEmptyDraftDoesNotAsk() throws {
        let (model, _) = try makeModel(session: session(draft: LayoutDocument.new(photos: [], title: "")))
        model.click("c.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        #expect(model.askingToContinueLayout == nil)
        #expect(photos(model) == ["c.jpg"])
    }

    @Test func testStartNewReplacesTheDraft() throws {
        let draft = LayoutDocument.new(photos: ["h.jpg", "a.jpg"], title: "Old")
        let (model, review) = try makeModel(session: session(draft: draft))
        let food = fx.food.id
        model.requestLayout(from: .category(food))
        #expect(model.askingToContinueLayout == .category(food))
        model.startNewLayout()
        #expect(model.askingToContinueLayout == nil)
        #expect(model.layoutEditor?.document.title == "Food")
        #expect(photos(model) == ["a.jpg", "c.jpg"] || photos(model) == ["c.jpg", "a.jpg"])
        model.layoutEditor?.requestClose()  // the draft saves when the editor closes
        #expect(review.session.layoutDraft?.title == "Food")
    }

    @Test func testCancelDropsTheQuestion() throws {
        let draft = LayoutDocument.new(photos: ["a.jpg"], title: "Old")
        let (model, review) = try makeModel(session: session(draft: draft))
        model.click("c.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        model.cancelLayoutRequest()
        #expect(model.askingToContinueLayout == nil && model.layoutEditor == nil)
        #expect(review.session.layoutDraft == draft)
        model.continueLayout()  // nothing asked: nothing opens
        model.startNewLayout()
        #expect(model.layoutEditor == nil)
    }

    // MARK: - While the layout is open

    @Test func testOpeningLayoutTurnsOffSortAndDone() throws {
        let (model, _) = try makeModel()
        #expect(model.canSortOrRescan && model.canDone)
        model.click("a.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        #expect(model.isEditing && !model.canSortOrRescan && !model.canDone)
        #expect(!model.canCreateLayout(from: .selection))
        if case .layout? = model.activeEditor {} else { Issue.record("The active editor must be the layout editor.") }
        #expect(model.editor == nil)
    }

    @Test func testTrashedPhotosAreNotAvailableToTheEditor() throws {
        let draft = LayoutDocument.new(photos: ["a.jpg", "b.jpg"], title: "")
        let (model, _) = try makeModel(session: session(trashed: [trash("b.jpg")], draft: draft))
        model.click("c.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        model.continueLayout()
        #expect(model.layoutEditor?.unavailableCount == 1)
    }

    @Test func testUndoGoesToTheLayoutEditor() throws {
        let (model, _) = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        let session = try #require(model.activeEditor?.session)
        #expect(!session.canUndo)
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: session.canUndo, reviewCanAct: true) == .nothing)
        model.layoutEditor?.setSpacing(12)
        #expect(model.activeEditor?.session.canUndo == true)
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: true, reviewCanAct: true) == .editor)
    }

    @Test func testSidebarChangeClosesTheLayoutAndSelects() throws {
        let (model, review) = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.requestLayout(from: .selection)
        model.layoutEditor?.setSpacing(12)
        let spacing = model.layoutEditor?.document.spacing
        model.selectedItem = .videos
        #expect(model.activeEditor == nil)  // no dialog: the draft is saved
        #expect(model.selectedItem == .videos)
        #expect(review.session.layoutDraft?.spacing == spacing)
        #expect(review.session.layoutDraft?.photoIDs == ["a.jpg"])
    }

    // MARK: - The menu

    @Test func testMenuOriginIsTheSelectionElseTheCurrentSet() throws {
        let food = fx.food.id
        let (model, _) = try makeModel()
        #expect(model.layoutMenuOrigin == nil)  // All Photos, nothing selected
        model.selectedItem = .category(food)
        #expect(model.layoutMenuOrigin == .category(food))
        model.click("a.jpg", modifiers: [])
        #expect(model.layoutMenuOrigin == .selection)
        model.selectedItem = .videos
        model.click("g.mov", modifiers: [])  // a video only: nothing to lay out
        #expect(model.layoutMenuOrigin == nil)
    }

    @Test func testMenuOriginOffForUnlistedItemsAndTheTrash() throws {
        let (model, _) = try makeModel(session: session(trashed: [trash("a.jpg")]))
        model.selectedItem = .recentlyDeleted
        #expect(model.layoutMenuOrigin == nil)
        model.requestLayoutFromMenu()
        #expect(model.layoutEditor == nil)
    }

    @Test func testContextMenuTargetsTheRightClickedPhotos() throws {
        let (model, _) = try makeModel()
        #expect(model.canCreateLayout(for: "a.jpg"))
        #expect(!model.canCreateLayout(for: "g.mov"))
        #expect(!model.canCreateLayout(for: "f.jpg"))
    }
}
