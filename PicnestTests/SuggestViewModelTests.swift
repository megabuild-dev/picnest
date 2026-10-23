import Foundation
import PicnestCore
import Testing
@testable import Picnest

@MainActor
struct SuggestViewModelTests {
    private let temp: TempDir
    private let catA = PicnestCore.Category(
        id: UUID(), displayName: "A", emoji: "🅰️", prompts: ["a"], exampleIDs: [], order: 0)
    private let catB = PicnestCore.Category(
        id: UUID(), displayName: "B", emoji: "🍜", prompts: ["b"], exampleIDs: [], order: 1)
    private static let locale = Locale(identifier: "en_US")

    /// Embeds the prompts of the first All topics candidate at e2, the prompts of "Workshop event" at e3,
    /// and every other text at e0.
    private struct PromptEmbedder: Embedder {
        let dimension = 6
        let e2Texts: Set<String>
        let e3Texts: Set<String>
        func embedImages(_ urls: [URL]) async throws -> [Vector] { urls.map { _ in [1, 0, 0, 0, 0, 0] } }
        func embedTexts(_ texts: [String]) async throws -> [Vector] {
            texts.map {
                e2Texts.contains($0) ? [0, 0, 1, 0, 0, 0] : e3Texts.contains($0) ? [0, 0, 0, 1, 0, 0] : [1, 0, 0, 0, 0, 0]
            }
        }
    }

    init() throws { temp = try TempDir() }

    /// 1 certain A photo, 9 Not sure photos around e2 ("p") and 8 around e3 ("q"): 2 suggestions.
    private func makeReview(extraCategoryNames: [String] = []) throws -> ReviewService {
        func unit(_ v: Vector) -> Vector { VectorMath.normalize(v) }
        let all = try CandidateRepository().load(.all)
        let first = try #require(all.first)
        let workshop = try #require(all.first { $0.displayName == "Workshop event" })
        var images: [MediaID: Vector] = ["a1.jpg": [1, 0, 0, 0, 0, 0]]
        for i in 1...9 { images["p\(i).jpg"] = unit([0, 0, 1, 0, 0.03 * Float(i), 0]) }
        for i in 1...8 { images["q\(i).jpg"] = unit([0, 0, 0, 1, 0, 0.03 * Float(i)]) }
        let source = try temp.folder("Photos")
        let sessions = SessionRepository(root: temp.url.appending(path: "Sessions"))
        let embeddings = EmbeddingRepository(
            embedder: PromptEmbedder(e2Texts: Set(first.prompts), e3Texts: Set(workshop.prompts)), cacheDirectory: sessions.directory(for: source))
        let extra = extraCategoryNames.enumerated().map {
            PicnestCore.Category(id: UUID(), displayName: $1, emoji: "🌳", prompts: [], exampleIDs: [], order: 10 + $0)
        }
        let categories = [catA, catB] + extra
        let prompts: [CategoryID: [Vector]] = [catA.id: [[1, 0, 0, 0, 0, 0]], catB.id: [[0, 1, 0, 0, 0, 0]]]
        let classify = ClassifyService(settings: .default)
        let states = classify.classify(states: [:], categories: categories, images: images, prompts: prompts)
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: categories,
            states: states,
            scan: ScanResult(
                media: images.keys.sorted().map {
                    MediaFile(id: $0, relativePath: $0, kind: .image, size: 10, modified: Date(timeIntervalSince1970: 1000))
                }, dates: [:], skipped: [:]),
            sortedAt: nil)
        return ReviewService(
            session: session, source: source, images: images, prompts: prompts, classify: classify,
            sessions: sessions, embeddings: embeddings)
    }

    private func makeModel(_ review: ReviewService, onAdded: @escaping ([CategoryID]) -> Void = { _ in })
        -> SuggestViewModel
    {
        SuggestViewModel(review: review, thumbnail: { _, _ in nil }, locale: Self.locale, onAdded: onAdded)
    }

    @Test func loadMakesRowsThatStartChecked() async throws {
        let review = try makeReview()
        let model = makeModel(review)
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .ready)
        #expect(model.rows.count == 2)
        #expect(model.rows.allSatisfy { $0.isOn })
        #expect(model.rows.map(\.ids.count) == [9, 8])
        #expect(model.addTitle == "Add 2 Categories")
        #expect(model.canAdd)
    }

    @Test func addTitleCountsCheckedRowsAndUsesSingular() async throws {
        let model = makeModel(try makeReview())
        await model.load()
        try #require(model.rows.count >= 2)
        model.rows[1].isOn = false
        #expect(model.addTitle == "Add 1 Category")
        model.rows[0].isOn = false
        #expect(model.addTitle == "Add 0 Categories")
        #expect(!model.canAdd)
    }

    @Test func renamingAndTogglingChangeWhatAddCreates() async throws {
        let review = try makeReview()
        var added: [CategoryID] = []
        let model = makeModel(review) { added = $0 }
        await model.load()
        try #require(model.rows.count >= 2)
        let firstIDs = model.rows[0].ids
        model.rows[0].isOn = false
        model.rows[1].name = "  Sky  "
        model.rows[1].emoji = "☁️"
        model.add()
        try #require(added.count == 1)
        let created = try #require(review.session.categories.first { $0.id == added[0] })
        #expect(created.displayName == "Sky")
        #expect(created.emoji == "☁️")
        #expect(review.session.categories.count == 3)
        try #require(firstIDs.count >= 1)
        #expect(review.session.states[firstIDs[0]]?.isNotSure == true)
        #expect(review.session.states["q1.jpg"] == .manual(created.id))
    }

    @Test func invalidEmojiFallsBackToTheSuggestedOne() async throws {
        let review = try makeReview()
        var added: [CategoryID] = []
        let model = makeModel(review) { added = $0 }
        await model.load()
        try #require(model.rows.count >= 2)
        let original = model.rows[1].emoji
        model.rows[0].isOn = false
        model.rows[1].emoji = "ab"
        model.add()
        try #require(added.count >= 1)
        #expect(review.session.categories.first { $0.id == added[0] }?.emoji == original)
    }

    @Test func commitEmojiRevertsAnInvalidEntry() async throws {
        let model = makeModel(try makeReview())
        await model.load()
        try #require(model.rows.count >= 1)
        let id = model.rows[0].id
        let original = model.rows[0].emoji
        model.rows[0].emoji = "ab"
        model.commitEmoji(of: id)
        #expect(model.rows[0].emoji == original)
        model.rows[0].emoji = " ☁️ "
        model.commitEmoji(of: id)
        #expect(model.rows[0].emoji == "☁️")
        model.rows[0].emoji = ""
        model.commitEmoji(of: id)
        #expect(model.rows[0].emoji == "☁️")
    }

    @Test func namesAreValidatedBeforeAdd() async throws {
        let review = try makeReview(extraCategoryNames: ["Sky"])
        let model = makeModel(review)
        await model.load()
        try #require(model.rows.count >= 2)
        model.rows[0].name = "   "
        #expect(model.nameHint(for: model.rows[0]) == "Enter a name.")
        #expect(!model.canAdd)
        model.rows[0].name = "sky"
        #expect(model.nameHint(for: model.rows[0]) == "This name is already used.")
        model.rows[0].name = "Cats"
        model.rows[1].name = " CATS "
        #expect(model.nameHint(for: model.rows[0]) == "This name is already used.")
        #expect(model.nameHint(for: model.rows[1]) == "This name is already used.")
        #expect(!model.canAdd)
        model.add()  // does nothing while a checked row is invalid
        #expect(review.session.categories.count == 3)
        model.rows[1].isOn = false  // an unchecked row is not checked for names
        #expect(model.nameHint(for: model.rows[0]) == nil)
        #expect(model.nameHint(for: model.rows[1]) == nil)
        #expect(model.canAdd)
    }

    @Test func addedNamesAreTheTrimmedOnes() async throws {
        let review = try makeReview()
        var added: [CategoryID] = []
        let model = makeModel(review) { added = $0 }
        await model.load()
        try #require(model.rows.count >= 2)
        model.rows[0].name = "Zoo"
        model.rows[1].name = "Sea"
        model.add()
        #expect(added.count == 2)
        #expect(Set(review.session.categories.map(\.displayName)).isSuperset(of: ["Zoo", "Sea"]))
    }

    @Test func fewPhotosShowTheEmptyState() async throws {
        let review = try makeReview()
        review.dontMove((1...9).map { "p\($0).jpg" } + (1...8).map { "q\($0).jpg" })
        let model = makeModel(review)
        await model.load()
        #expect(model.state == .empty)
        #expect(SuggestViewModel.emptyText
            == "No new groups found. Move the photos by hand or make a category with New Category…")
    }

    @Test func loadRunsOnce() async throws {
        let review = try makeReview()
        let model = makeModel(review)
        await model.load()
        try #require(model.rows.count >= 1)
        model.rows[0].name = "Edited"
        await model.load()
        #expect(model.rows[0].name == "Edited")
    }
}
