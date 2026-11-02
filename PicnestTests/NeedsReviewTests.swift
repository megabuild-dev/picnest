import Foundation
import PicnestCore
import Testing
@testable import Picnest

/// Needs Review: search and the 3 issue filters (UI redesign 4.3). Real small JPEG files, because the
/// similar-photos filter reads the Duplicates data.
@MainActor
struct NeedsReviewTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let classify = ClassifyService(settings: .default)
    private let food = PicnestCore.Category(id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 0)
    private let documents = PicnestCore.Category(id: UUID(), displayName: "Documents", emoji: "🧾", prompts: ["d"], exampleIDs: [], order: 1)
    private let pets = PicnestCore.Category(id: UUID(), displayName: "Pets", emoji: "🐶", prompts: ["p"], exampleIDs: [], order: 2)

    init() throws { temp = try TempDir() }

    /// `score` is the raw best score. Below `ClassifySettings.default.minScore` (0.22) the match is weak.
    private func assignment(_ category: PicnestCore.Category, _ percent: Int, score: Float = 0.3) -> Assignment {
        Assignment(categoryID: category.id, score: score, secondCategoryID: nil, secondScore: nil,
                   percent: percent, uncertain: true)
    }

    /// Needs Review: Food trip1 50%, trip2 40% (weak score), n3 45%; Documents trip4 70% (weak score), n5 35%;
    /// Pets n6 20%, x1 (a placeholder guess of a photo with no vector: score 0, percent 0).
    /// So percent and weak score disagree for trip2 (40%, weak), trip4 (70%, weak) and n3 (45%, not weak).
    /// n3 and trip4 are similar photos. ok.jpg is certain.
    private func makeModel(search: DuplicatesViewModel.Search? = nil) throws -> ReviewViewModel {
        let source = try temp.folder("Photos")
        let spec: [(String, PicnestCore.Category, Int, Float)] = [
            ("trip1.jpg", food, 50, 0.3), ("trip2.jpg", food, 40, 0.1), ("n3.jpg", food, 45, 0.3),
            ("trip4.jpg", documents, 70, 0.1), ("n5.jpg", documents, 35, 0.3), ("n6.jpg", pets, 20, 0.3),
            ("x1.jpg", pets, 0, 0),
        ]
        var states: [MediaID: PhotoState] = [
            "ok.jpg": .auto(Assignment(categoryID: food.id, score: 0.3, secondCategoryID: nil, secondScore: nil,
                                       percent: 90, uncertain: false)),
        ]
        for (name, category, percent, score) in spec { states[name] = .auto(assignment(category, percent, score: score)) }
        let names = spec.map(\.0) + ["ok.jpg"]
        var images: [MediaID: Vector] = [:]
        var media: [MediaFile] = []
        for (i, name) in names.enumerated() {
            let url = source.appending(path: name)
            try writeTestJPEG(to: url, red: CGFloat(i) / 10, green: 0.2, blue: 1 - CGFloat(i) / 10, size: 16 + i)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            media.append(MediaFile(id: name, relativePath: name, kind: .image, size: Int64(values.fileSize ?? 1),
                                   modified: try #require(values.contentModificationDate)))
            var v = Vector(repeating: 0, count: 8)
            v[i] = 1
            images[name] = v
        }
        // n3 and trip4 look alike (cosine 0.97).
        images["n3.jpg"] = [0, 0, 0, 1, 0, 0, 0, 0]
        images["trip4.jpg"] = [0, 0, 0, 0.97, 0.2431, 0, 0, 0]
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday,
            categories: [food, documents, pets], states: states,
            scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil)
        let review = ReviewService(
            session: session, source: source, images: images, prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")))
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
        let model = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, photoEdits: environment.photoEdits, layoutExport: environment.layoutExport, app: AppModel(environment: environment), onRescan: {},
            defaults: suite.defaults, duplicateSearch: search)
        model.selectedItem = .notSure
        return model
    }

    private func shown(_ model: ReviewViewModel) -> [[MediaID]] { model.notSureGroups.map(\.ids) }

    // MARK: - Search

    @Test func testSearchNarrowsGroups() throws {
        let model = try makeModel()
        model.searchText = "trip"
        #expect(model.notSureGroups.map(\.categoryName) == ["Food", "Documents"])
        #expect(shown(model) == [["trip2.jpg", "trip1.jpg"], ["trip4.jpg"]])
        #expect(model.visibleIDs == ["trip2.jpg", "trip1.jpg", "trip4.jpg"])
    }

    @Test func testSelectGroupSelectsOnlyMatches() throws {
        let model = try makeModel()
        model.searchText = "trip"
        model.selectGroup(model.notSureGroups[0])
        #expect(model.selection == ["trip1.jpg", "trip2.jpg"])
    }

    @Test func testAcceptGroupAcceptsOnlyMatches() throws {
        let model = try makeModel()
        model.searchText = "trip"
        model.acceptGroup(model.notSureGroups[0])
        #expect(model.count(of: .changedByYou) == 2)
        #expect(model.count(of: .notSure) == 5)
        model.searchText = ""
        #expect(shown(model).flatMap { $0 }.contains("n3.jpg"))
        #expect(model.notSureGroups.first { $0.categoryName == "Food" }?.ids == ["n3.jpg"])
    }

    @Test func testAcceptAllAcceptsOnlyMatches() throws {
        let model = try makeModel()
        model.searchText = "trip"
        model.acceptAll()
        #expect(model.count(of: .changedByYou) == 3)
        model.searchText = ""
        #expect(Set(model.visibleIDs) == ["n3.jpg", "n5.jpg", "n6.jpg", "x1.jpg"])
    }

    @Test func testClearingSearchRestoresGroups() throws {
        let model = try makeModel()
        let all = shown(model)
        model.searchText = "trip"
        #expect(shown(model) != all)
        model.searchText = ""
        #expect(shown(model) == all)
    }

    @Test func testSelectionHiddenBySearchIsDroppedAndNotAccepted() throws {
        let model = try makeModel()
        model.click("n6.jpg", modifiers: [])
        model.searchText = "trip"
        #expect(model.selection.isEmpty)
        model.acceptSelection()
        #expect(model.count(of: .changedByYou) == 0)
        #expect(model.count(of: .notSure) == 7)
    }

    @Test func testEmptyStateNoResultsVersusNothingLeft() throws {
        let model = try makeModel()
        model.searchText = "zzz"
        #expect(model.emptyState == .noResults)
        model.searchText = ""
        model.acceptAll()
        #expect(model.emptyState == .nothingToReview)
        model.searchText = "zzz"
        #expect(model.emptyState == .nothingToReview)
    }

    @Test func testSearchStaysWhenEnteringNeedsReview() throws {
        let model = try makeModel()
        model.selectedItem = .all
        model.searchText = "trip"
        model.selectedItem = .notSure
        #expect(model.searchText == "trip")
    }

    // MARK: - Issue filters

    @Test func testNilIssueShowsAllNeedsReview() throws {
        let model = try makeModel()
        #expect(model.reviewIssue == nil)
        #expect(model.visibleIDs.count == 7)
        #expect(ReviewIssue.allCases.count == 3)
    }

    @Test func testIssueFilterLowConfidence() throws {
        let model = try makeModel()
        model.reviewIssue = .lowConfidence
        // The weak score decides, not the percent: trip4 has 70% and shows; n3 has 45% and does not.
        #expect(Set(model.visibleIDs) == ["trip2.jpg", "trip4.jpg"])
        model.reviewIssue = nil
        #expect(model.visibleIDs.count == 7)
    }

    @Test func testIssueFilterNoCategory() throws {
        let model = try makeModel()
        model.reviewIssue = .noCategory
        #expect(model.visibleIDs == ["x1.jpg"])
        #expect(model.notSureGroups.map(\.categoryName) == ["Pets"])
    }

    @Test func testIssueFilterSimilar() async throws {
        let model = try makeModel()
        model.reviewIssue = .similarPhotos
        #expect(model.visibleIDs.isEmpty)  // Not found yet: no data.
        await model.duplicates.find()
        #expect(Set(model.visibleIDs) == ["n3.jpg", "trip4.jpg"])
        model.reviewIssue = nil
        #expect(model.visibleIDs.count == 7)
    }

    @Test func testIssueCombinesWithSearchAndAccept() async throws {
        let model = try makeModel()
        await model.duplicates.find()
        model.searchText = "trip"
        model.reviewIssue = .lowConfidence
        #expect(Set(model.visibleIDs) == ["trip2.jpg", "trip4.jpg"])
        model.reviewIssue = .similarPhotos
        #expect(model.visibleIDs == ["trip4.jpg"])
        model.reviewIssue = .lowConfidence
        model.acceptAll()
        #expect(model.count(of: .changedByYou) == 2)
        #expect(model.count(of: .notSure) == 5)
    }

    @Test func testLeavingTheSimilarFilterCancelsTheSearch() async throws {
        let model = try makeModel()
        model.reviewIssue = .similarPhotos
        let search = try #require(model.similarSearch)
        model.reviewIssue = nil
        #expect(search.isCancelled)
        #expect(model.similarSearch == nil)
        await search.value
        #expect(model.duplicates.state == .idle)  // A cancelled search is idle, not found and not stuck finding.
        #expect(model.visibleIDs.count == 7)
    }

    @Test func testChoosingAnotherIssueOrItemCancelsTheSearch() async throws {
        let model = try makeModel()
        model.reviewIssue = .similarPhotos
        let first = try #require(model.similarSearch)
        model.reviewIssue = .lowConfidence
        #expect(first.isCancelled)
        model.reviewIssue = .similarPhotos
        let second = try #require(model.similarSearch)
        model.selectedItem = .all  // Leaving Needs Review clears the issue.
        #expect(second.isCancelled)
        #expect(model.similarSearch == nil)
        await first.value
        await second.value
        #expect(model.duplicates.state == .idle)
    }

    @Test func testSimilarSearchRunsAgainAfterACancel() async throws {
        let model = try makeModel()
        model.reviewIssue = .similarPhotos
        let first = try #require(model.similarSearch)
        model.reviewIssue = nil
        await first.value
        model.reviewIssue = .similarPhotos
        let second = try #require(model.similarSearch)
        await second.value
        #expect(Set(model.visibleIDs) == ["n3.jpg", "trip4.jpg"])
        #expect(model.duplicates.state == .ready)
        #expect(model.similarSearch != nil)  // Finished: the task stays until the filter changes, and is harmless.
    }

    /// A duplicate search that pauses until the test resumes it, 1 run at a time (first in, first out).
    @MainActor private final class PausedSearch {
        private(set) var calls = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []

        var search: DuplicatesViewModel.Search {
            { [self] _ in
                calls += 1
                await withCheckedContinuation { waiting.append($0) }
                return []
            }
        }

        func resumeOldest() { if !waiting.isEmpty { waiting.removeFirst().resume() } }
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() { await Task.yield() }
    }

    private func isFinding(_ d: DuplicatesViewModel) -> Bool {
        if case .finding = d.state { return true }
        return false
    }

    // Scenario A: Similar photos runs, then the user opens Duplicates. The search must start again, not stay idle.
    @Test func testOpeningDuplicatesWhileTheSimilarSearchRunsStartsANewSearch() async throws {
        let stub = PausedSearch()
        let model = try makeModel(search: stub.search)
        model.reviewIssue = .similarPhotos
        await wait { stub.calls == 1 }
        model.selectedItem = .duplicates
        #expect(model.duplicates.state == .idle)  // Freed at once.
        let view = Task { await model.duplicates.find() }  // The Duplicates view starts its search.
        await wait { stub.calls == 2 }
        #expect(isFinding(model.duplicates))
        stub.resumeOldest()  // The stale run ends: it writes nothing.
        for _ in 0..<200 { await Task.yield() }  // Let the stale run end.
        #expect(isFinding(model.duplicates))
        stub.resumeOldest()
        await view.value
        #expect(model.duplicates.state == .empty)
        #expect(model.duplicates.findCount == 2)
    }

    // Scenario A2: the Duplicates view leaves and comes back before the old run ends.
    @Test func testLeavingAndReturningToDuplicatesStartsANewSearch() async throws {
        let stub = PausedSearch()
        let model = try makeModel(search: stub.search)
        let first = Task { await model.duplicates.find() }
        await wait { stub.calls == 1 }
        first.cancel()  // The view task is cancelled when the view goes away.
        await wait { model.duplicates.state == .idle }
        #expect(model.duplicates.state == .idle)
        let second = Task { await model.duplicates.find() }
        await wait { stub.calls == 2 }
        stub.resumeOldest()
        await first.value
        #expect(isFinding(model.duplicates))  // The old run did not set idle.
        stub.resumeOldest()
        await second.value
        #expect(model.duplicates.state == .empty)
        #expect(model.duplicates.findCount == 2)
    }

    // Scenario B: Similar photos off and on again quickly.
    @Test func testTogglingTheSimilarFilterQuicklyKeepsOneRunningSearch() async throws {
        let stub = PausedSearch()
        let model = try makeModel(search: stub.search)
        model.reviewIssue = .similarPhotos
        await wait { stub.calls == 1 }
        let first = try #require(model.similarSearch)
        model.reviewIssue = nil
        model.reviewIssue = .similarPhotos
        let second = try #require(model.similarSearch)
        await wait { stub.calls == 2 }
        stub.resumeOldest()
        await first.value
        #expect(isFinding(model.duplicates))
        stub.resumeOldest()
        await second.value
        #expect(model.duplicates.state == .empty)
        #expect(model.duplicates.findCount == 2)
    }

    @Test func testLeavingNeedsReviewClearsIssue() throws {
        let model = try makeModel()
        model.reviewIssue = .noCategory
        model.selectedItem = .all
        #expect(model.reviewIssue == nil)
    }

    @Test func testIssueEmptyStateIsNoResults() throws {
        let model = try makeModel()
        model.reviewIssue = .similarPhotos
        #expect(model.emptyState == .findingSimilar)  // Not searched yet.
    }

    @Test func testEmptyStateNoResultsAfterSimilarSearch() async throws {
        let model = try makeModel()
        await model.duplicates.find()
        model.reviewIssue = .similarPhotos
        model.searchText = "n5"
        #expect(model.emptyState == .noResults)
    }

    @Test func testSimilarEmptyStateFollowsSearchPhase() {
        #expect(ReviewViewModel.similarEmptyState(for: .idle) == .findingSimilar)
        #expect(ReviewViewModel.similarEmptyState(for: .finding(done: 1, total: 2)) == .findingSimilar)
        #expect(ReviewViewModel.similarEmptyState(for: .failed("Disk error")) == .similarSearchFailed("Disk error"))
        #expect(ReviewViewModel.similarEmptyState(for: .ready) == .noResults)
        #expect(ReviewViewModel.similarEmptyState(for: .empty) == .noResults)
    }

    @Test func testEmptyFolderInNeedsReviewShowsNothingLeft() throws {
        let model = try makeModel()
        model.selectedItem = .all
        model.clearReviewFilters()
        // A model with no photos at all.
        let source = try temp.folder("Empty")
        let review = ReviewService(
            session: Session(sourcePath: source.path(percentEncoded: false), candidateList: .everyday,
                             categories: [food], states: [:],
                             scan: ScanResult(media: [], dates: [:], skipped: [:]), sortedAt: nil),
            source: source, images: [:], prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions2")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache2")))
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions2"), defaults: suite.defaults)
        let empty = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, photoEdits: environment.photoEdits, layoutExport: environment.layoutExport, app: AppModel(environment: environment), onRescan: {},
            defaults: suite.defaults)
        empty.selectedItem = .notSure
        #expect(empty.emptyState == .nothingToReview)
    }

    @Test func testIssueCountsAndAvailability() async throws {
        let model = try makeModel()
        #expect(model.reviewIssueCount(.lowConfidence) == 2)
        #expect(model.reviewIssueCount(.noCategory) == 1)
        #expect(model.isReviewIssueAvailable(.lowConfidence))
        #expect(model.isReviewIssueAvailable(.noCategory))
        #expect(model.isReviewIssueAvailable(.similarPhotos))  // Unknown until the search runs.
        await model.duplicates.find()
        #expect(model.reviewIssueCount(.similarPhotos) == 2)
        // Accept the weak and placeholder photos: those menus have no match left.
        model.reviewIssue = .lowConfidence
        model.acceptAll()
        model.reviewIssue = nil
        #expect(model.reviewIssueCount(.lowConfidence) == 0)
        #expect(!model.isReviewIssueAvailable(.lowConfidence))
        model.click("x1.jpg", modifiers: [])
        model.dontMoveSelection()
        #expect(!model.isReviewIssueAvailable(.noCategory))
    }

    @Test func testSelectionPreviewHoldsUpToThreePhotosInGridOrder() throws {
        let model = try makeModel()
        #expect(model.selectionPreviewIDs.isEmpty)
        model.selectAll()
        #expect(model.selectionPreviewIDs == Array(model.visibleIDs.prefix(3)))
        model.click("n6.jpg", modifiers: [])
        #expect(model.selectionPreviewIDs == ["n6.jpg"])
    }

    // MARK: - VoiceOver

    @Test func testUncertainTileLabelHasNeedsReviewAndPercent() throws {
        let model = try makeModel()
        let label = model.tile("trip1.jpg").accessibilityLabel
        #expect(label.contains("Needs Review"))
        #expect(label.contains("50%"))
    }
}
