import Foundation
import PicnestCore
import Testing
@testable import Picnest

/// Favorites, collections, and Recently Deleted in the view model (UI redesign 3.6). The fixture has the
/// 8 files a.jpg ... h.jpg of `ReviewFixture`.
@MainActor
struct CollectionsViewModelTests {
    private let fx: ReviewFixture

    init() throws { fx = try ReviewFixture() }

    private func make(
        trashOps: FakeTrashFileOps = FakeTrashFileOps(), _ edit: @escaping (inout Session) -> Void = { _ in }
    ) throws -> (model: ReviewViewModel, review: ReviewService) {
        try fx.makeModelAndReview(trashOps: trashOps, session: { source in
            var session = fx.makeSession(source: source)
            edit(&session)
            return session
        })
    }

    /// Selects the photos like clicks do: the first one, then the others with ⌘.
    private func select(_ model: ReviewViewModel, _ ids: [MediaID]) {
        model.clearSelection()
        for (index, id) in ids.enumerated() { model.click(id, modifiers: index == 0 ? [] : .command) }
    }

    private func collection(_ name: String, _ ids: [MediaID], order: Int = 0) -> PhotoCollection {
        PhotoCollection(name: name, memberIDs: ids, order: order)
    }

    @Test func testFavoritesListsOnlyVisibleFavorites() throws {
        // b.jpg is trashed, so it is not listed even though it is a favorite (Review Focus 2).
        let (model, _) = try make { session in
            session.favoriteIDs = ["a.jpg", "b.jpg", "c.jpg"]
            session.trashed = [TrashedPhoto(mediaID: "b.jpg", trashPath: "/t/b", time: Date())]
        }
        model.selectedItem = .favorites
        model.sortOrder = .name
        #expect(model.visibleIDs == ["a.jpg", "c.jpg"])
        #expect(model.title == "Favorites")
    }

    @Test func testCollectionListsItsMembers() throws {
        let box = collection("Trip", ["g.mov", "a.jpg", "zzz.jpg"])
        let (model, _) = try make { $0.collections = [box] }
        model.selectedItem = .collection(box.id)
        model.sortOrder = .name
        #expect(model.visibleIDs == ["a.jpg", "g.mov"])
        #expect(model.title == "Trip")
        model.searchText = "g.m"
        #expect(model.visibleIDs == ["g.mov"])
    }

    @Test func testSidebarCountsForNewItems() throws {
        let trip = collection("Trip", ["a.jpg", "b.jpg", "c.jpg"], order: 0)
        let empty = collection("Empty", [], order: 1)
        let (model, _) = try make { session in
            session.favoriteIDs = ["a.jpg", "b.jpg"]
            session.collections = [trip, empty]
            session.trashed = [TrashedPhoto(mediaID: "b.jpg", trashPath: "/t/b", time: Date())]
        }
        let counts = model.sidebarCounts
        #expect(counts[.favorites] == 1)
        #expect(counts[.collection(trip.id)] == 2)
        #expect(counts[.collection(empty.id)] == 0)
        #expect(counts[.recentlyDeleted] == 1)
        #expect(model.collections.map(\.name) == ["Trip", "Empty"])
    }

    @Test func testRecentlyDeletedListsNewestFirst() throws {
        let now = Date()
        let (model, _) = try make { session in
            session.trashed = [
                TrashedPhoto(mediaID: "a.jpg", trashPath: "/t/a", time: now.addingTimeInterval(-60)),
                TrashedPhoto(mediaID: "c.jpg", trashPath: "/t/c", time: now),
                TrashedPhoto(mediaID: "b.jpg", trashPath: "/t/b", time: now),
            ]
        }
        model.selectedItem = .recentlyDeleted
        #expect(model.visibleIDs == ["b.jpg", "c.jpg", "a.jpg"])
        #expect(model.bodyKind == .recentlyDeleted)
        #expect(model.title == "Recently Deleted")
    }

    @Test func testRecentlyDeletedHonorsSearch() throws {
        let (model, _) = try make { session in
            session.trashed = [
                TrashedPhoto(mediaID: "a.jpg", trashPath: "/t/a", time: Date()),
                TrashedPhoto(mediaID: "c.jpg", trashPath: "/t/c", time: Date()),
            ]
        }
        model.selectedItem = .recentlyDeleted
        model.searchText = "c.j"
        #expect(model.visibleIDs == ["c.jpg"])
        model.searchText = "zzz"
        #expect(model.visibleIDs.isEmpty)
        #expect(model.emptyState == .noResults)
    }

    @Test func testToggleFavoriteSelection() throws {
        let (model, review) = try make()
        select(model, ["a.jpg", "b.jpg"])
        model.toggleFavoriteSelection()
        #expect(review.session.favoriteIDs == ["a.jpg", "b.jpg"])
        #expect(model.isFavorite("a.jpg"))
        model.toggleFavoriteSelection()
        #expect(review.session.favoriteIDs.isEmpty)
        #expect(!model.isFavorite("a.jpg"))
    }

    @Test func testNewCollectionAddsTheSelection() throws {
        let (model, review) = try make()
        select(model, ["a.jpg", "c.jpg"])
        model.requestNewCollection(adding: model.visibleIDs.filter(model.selection.contains))
        #expect(model.editingCollection != nil)
        #expect(!model.saveCollection(name: "  "))
        #expect(model.editingCollection != nil)
        #expect(model.saveCollection(name: " Trip "))
        #expect(model.editingCollection == nil)
        #expect(review.session.collections.map(\.name) == ["Trip"])
        #expect(Set(review.session.collections[0].memberIDs) == ["a.jpg", "c.jpg"])
        #expect(model.validateCollectionName("trip", excluding: nil) == .duplicate)
        #expect(model.validateCollectionName("trip", excluding: review.session.collections[0].id) == nil)
        #expect(model.validateCollectionName(" ", excluding: nil) == .empty)
    }

    @Test func testRenameCollection() throws {
        let box = collection("Trip", ["a.jpg"])
        let other = collection("Home", [], order: 1)
        let (model, review) = try make { $0.collections = [box, other] }
        model.requestRenameCollection(box.id)
        #expect(model.collectionSheetName == "Trip")
        #expect(!model.saveCollection(name: "home"))
        #expect(model.saveCollection(name: "Holiday"))
        #expect(review.session.collections.first { $0.id == box.id }?.name == "Holiday")
    }

    @Test func testDeleteCollectionTitleNamesTheCollection() throws {
        let box = collection("Trip", [])
        let (model, _) = try make { $0.collections = [box] }
        #expect(model.deleteCollectionTitle(for: box.id) == "Delete the collection “Trip”?")
    }

    @Test func testAddSelectionAndDrop() throws {
        let box = collection("Trip", [])
        let (model, review) = try make { $0.collections = [box] }
        select(model, ["a.jpg"])
        model.addSelection(to: box.id)
        #expect(review.session.collections[0].memberIDs == ["a.jpg"])
        #expect(model.dropOnCollection(["b.jpg", "c.jpg"], box.id))
        #expect(review.session.collections[0].memberIDs == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(!model.dropOnCollection([], box.id))
        #expect(!model.dropOnCollection(["a.jpg"], UUID()))
    }

    @Test func testDeletingTheSelectedCollectionSelectsAllPhotos() throws {
        let box = collection("Trip", ["a.jpg"])
        let (model, review) = try make { $0.collections = [box] }
        model.selectedItem = .collection(box.id)
        model.deletingCollection = box.id
        model.deleteCollection(box.id)
        #expect(model.selectedItem == .all)
        #expect(model.deletingCollection == nil)
        #expect(review.session.collections.isEmpty)
        #expect(model.count(of: .all) == 8)
    }

    @Test func testRemoveFromCollectionOnlyInACollection() throws {
        let box = collection("Trip", ["a.jpg", "b.jpg"])
        let (model, review) = try make { $0.collections = [box] }
        select(model, ["a.jpg"])
        model.removeSelectionFromCollection()  // Not in a collection: nothing happens.
        #expect(review.session.collections[0].memberIDs == ["a.jpg", "b.jpg"])
        model.selectedItem = .collection(box.id)
        select(model, ["a.jpg"])
        model.removeSelectionFromCollection()
        #expect(review.session.collections[0].memberIDs == ["b.jpg"])
        #expect(model.selection.isEmpty)
    }

    @Test func testEmptyStatesOfNewItems() throws {
        let box = collection("Trip", [])
        let (model, _) = try make { $0.collections = [box] }
        model.selectedItem = .favorites
        #expect(model.emptyState == .noFavorites)
        model.selectedItem = .collection(box.id)
        #expect(model.emptyState == .emptyCollection)
        model.selectedItem = .recentlyDeleted
        #expect(model.emptyState == .nothingDeleted)
        model.searchText = "x"
        #expect(model.emptyState == .noResults)
    }

    @Test func testStartOverMessageNamesFavoritesAndCollections() throws {
        let (model, review) = try make()
        let text = "The app scans the folder again and proposes new categories. Your categories and picks are lost."
            + " Your favorites and collections are lost too."
        #expect(model.startOverMessage == text)
        review.markSorted(at: Date())
        #expect(model.startOverMessage == text + " The last sort can no longer be undone.")
    }

    @Test func testNewItemsHideChipsAndShowSlider() throws {
        let box = collection("Trip", [])
        let (model, _) = try make { $0.collections = [box] }
        for item in [ReviewViewModel.SidebarItem.favorites, .collection(box.id), .recentlyDeleted] {
            model.selectedItem = item
            #expect(!model.showsFilterChips)
            #expect(model.showsThumbnailSlider(layout: .grid))
            #expect(!model.showsThumbnailSlider(layout: .list))
            #expect(model.filter == .all)
        }
    }

    @Test func testPutBackSelectionReportsErrors() async throws {
        let (model, review) = try make { session in
            session.trashed = [TrashedPhoto(mediaID: "a.jpg", trashPath: "/t/a", time: Date())]
        }
        model.selectedItem = .recentlyDeleted
        select(model, ["a.jpg"])
        model.putBackSelection()
        await model.settled()
        // The fake Trash has no file at /t/a, so the photo cannot come back and stays listed.
        #expect(model.putBackErrorMessage != nil)
        #expect(review.session.trashedIDs == ["a.jpg"])
        #expect(model.visibleIDs == ["a.jpg"])
    }

    // MARK: - Favorite actions and thumbnails of trashed photos (UI redesign 3.8)

    @Test func testToggleFavoriteOfOnePhotoLeavesTheSelection() throws {
        let (model, review) = try make()
        select(model, ["a.jpg", "b.jpg"])
        model.toggleFavorite("c.jpg")
        #expect(review.session.favoriteIDs == ["c.jpg"])
        #expect(model.selection == ["a.jpg", "b.jpg"])
        model.toggleFavorite("c.jpg")
        #expect(review.session.favoriteIDs.isEmpty)
    }

    @Test func testFavoriteMenuTitleFollowsTheTargets() throws {
        let (model, _) = try make { $0.favoriteIDs = ["a.jpg"] }
        #expect(model.allFavorites(["a.jpg"]))
        #expect(!model.allFavorites(["a.jpg", "b.jpg"]))
        #expect(!model.allFavorites([]))
    }

    @Test func testTileLabelNamesAFavorite() throws {
        let (model, _) = try make { $0.favoriteIDs = ["a.jpg"] }
        #expect(model.tile("a.jpg").accessibilityLabel.contains("Favorite"))
        #expect(!model.tile("b.jpg").accessibilityLabel.contains("Favorite"))
    }

    // MARK: - Add Photos (UI redesign 3.9)

    @Test func testAddPhotosCandidatesLeaveOutMembers() throws {
        let box = collection("Trip", ["a.jpg", "b.jpg"])
        let (model, _) = try make { session in
            session.collections = [box]
            session.trashed = [TrashedPhoto(mediaID: "c.jpg", trashPath: "/t/c", time: Date())]
        }
        let candidates = model.addPhotosCandidates(for: .collection(box.id))
        // Not the members, not the trashed c.jpg.
        #expect(Set(candidates) == ["d.jpg", "e.jpg", "f.jpg", "g.mov", "h.jpg"])
        #expect(candidates.count == 5)
        // Food has a.jpg (certain guess) and c.jpg (chosen); b.jpg is only a weak guess.
        let forCategory = model.addPhotosCandidates(for: .category(fx.food.id))
        #expect(!forCategory.contains("a.jpg") && !forCategory.contains("c.jpg"))
        #expect(forCategory.contains("b.jpg") && forCategory.contains("h.jpg"))
    }

    @Test func testAddPhotosToCategoryMakesManualPicks() throws {
        let (model, review) = try make()
        let category = fx.documents.id
        model.addingPhotos = .category(category)
        model.addPhotos(["a.jpg", "b.jpg"], to: .category(category))
        #expect(review.session.states["a.jpg"] == .manual(category))
        #expect(review.session.states["b.jpg"] == .manual(category))
        #expect(model.addingPhotos == nil)
    }

    @Test func testAddPhotosToCollectionAppendsMembers() throws {
        let box = collection("Trip", ["a.jpg"])
        let (model, review) = try make { $0.collections = [box] }
        model.addingPhotos = .collection(box.id)
        model.addPhotos(["b.jpg", "c.jpg"], to: .collection(box.id))
        #expect(review.session.collections[0].memberIDs == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(model.addingPhotos == nil)
    }

    @Test func testCreateCollectionInsteadKeepsTheCategoryAndOpensTheSheetAfterTheEditSheet() throws {
        let (model, review) = try make()
        model.editingCategory = fx.food.id
        model.createCollectionInstead(of: fx.food.id)
        // The edit sheet closes first. The collection sheet waits for its dismissal.
        #expect(model.editingCategory == nil)
        #expect(model.editingCollection == nil)
        model.openPendingCollection()
        #expect(model.editingCollection == .new(name: "Food", adding: []))
        model.openPendingCollection()  // Once only.
        #expect(review.session.categories.contains { $0.id == fx.food.id && $0.displayName == "Food" })
        #expect(review.session.collections.isEmpty)
    }

    @Test func testSelectedCollectionFollowsTheSidebarItem() throws {
        let box = collection("Trip", [])
        let (model, _) = try make { $0.collections = [box] }
        #expect(model.selectedCollection == nil)
        model.selectedItem = .collection(box.id)
        #expect(model.selectedCollection?.name == "Trip")
    }
}
