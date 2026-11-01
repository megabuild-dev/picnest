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

    private func assignment(_ category: PicnestCore.Category?, _ percent: Int) -> Assignment {
        Assignment(categoryID: category?.id ?? UUID(), score: 0.3, secondCategoryID: nil, secondScore: nil,
                   percent: percent, uncertain: true)
    }

    /// Needs Review: Food trip1 50%, trip2 40%, n3 45%; Documents trip4 30%, n5 35%; Pets n6 20%;
    /// x1 60% with a best guess that is not a category. n3 and trip4 are similar photos. ok.jpg is certain.
    private func makeModel() throws -> ReviewViewModel {
        let source = try temp.folder("Photos")
        let spec: [(String, PicnestCore.Category?, Int)] = [
            ("trip1.jpg", food, 50), ("trip2.jpg", food, 40), ("n3.jpg", food, 45),
            ("trip4.jpg", documents, 30), ("n5.jpg", documents, 35), ("n6.jpg", pets, 20), ("x1.jpg", nil, 60),
        ]
        var states: [MediaID: PhotoState] = [
            "ok.jpg": .auto(Assignment(categoryID: food.id, score: 0.3, secondCategoryID: nil, secondScore: nil,
                                       percent: 90, uncertain: false)),
        ]
        for (name, category, percent) in spec { states[name] = .auto(assignment(category, percent)) }
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
            library: environment.library, app: AppModel(environment: environment), onRescan: {},
            defaults: suite.defaults)
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
        model.selectGroup(at: 0)
        #expect(model.selection == ["trip1.jpg", "trip2.jpg"])
    }

    @Test func testAcceptGroupAcceptsOnlyMatches() throws {
        let model = try makeModel()
        model.searchText = "trip"
        model.acceptGroup(at: 0)
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
        model.click("x1.jpg", modifiers: [])  // Its best guess is no category, so Accept cannot take it.
        model.moveSelection(to: food.id)
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
        #expect(Set(model.visibleIDs) == ["trip2.jpg", "n3.jpg", "trip4.jpg", "n5.jpg", "n6.jpg"])
        model.reviewIssue = nil
        #expect(model.visibleIDs.count == 7)
    }

    @Test func testIssueFilterNoCategory() throws {
        let model = try makeModel()
        model.reviewIssue = .noCategory
        #expect(model.visibleIDs == ["x1.jpg"])
        #expect(model.notSureGroups.map(\.categoryName) == ["Unknown"])
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

    @Test func testLeavingNeedsReviewClearsIssue() throws {
        let model = try makeModel()
        model.reviewIssue = .noCategory
        model.selectedItem = .all
        #expect(model.reviewIssue == nil)
    }

    @Test func testIssueEmptyStateIsNoResults() throws {
        let model = try makeModel()
        model.reviewIssue = .similarPhotos
        #expect(model.emptyState == .noResults)
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
