import Foundation
import Testing
@testable import PicnestCore

/// Spec 4.8: suggested categories for the "Not sure" photos.
struct SuggestionServiceTests {
    private static let dim = 8
    private let service = SuggestionService()

    private static func axis(_ i: Int) -> Vector {
        var v = Vector(repeating: 0, count: dim)
        v[i] = 1
        return v
    }

    /// The unit vector halfway between axes `a` and `b`.
    private static func between(_ a: Int, _ b: Int) -> Vector {
        VectorMath.normalize(zip(axis(a), axis(b)).map { $0 + $1 })
    }

    /// `count` noisy unit vectors around axis `a`, keyed "<prefix>1.jpg", "<prefix>2.jpg", ...
    private static func blob(_ prefix: String, around a: Int, count: Int, seed: UInt64) -> [MediaID: Vector] {
        var rng = SplitMix64(seed: seed)
        var out: [MediaID: Vector] = [:]
        for i in 1...count {
            var v = axis(a)
            for d in 0..<dim { v[d] += Float.random(in: -0.05...0.05, using: &rng) }
            out["\(prefix)\(i).jpg"] = VectorMath.normalize(v)
        }
        return out
    }

    private static func merged(_ parts: [MediaID: Vector]...) -> [MediaID: Vector] {
        parts.reduce(into: [:]) { result, part in result.merge(part) { first, _ in first } }
    }

    private func candidate(_ name: String, _ emoji: String = "🙂") -> Candidate {
        Candidate(displayName: name, emoji: emoji, prompts: ["a photo of \(name.lowercased())"])
    }

    private func suggest(
        _ notSure: [MediaID: Vector], _ candidates: [(Candidate, Vector)], existing: Set<String> = []
    ) -> [CategorySuggestion] {
        service.suggest(
            notSure: notSure, candidates: candidates.map(\.0), candidateVectors: candidates.map { [$0.1] },
            existingNames: existing, seed: 42)
    }

    @Test func fewerThan7NotSureSuggestsNothing() {
        let photos = Self.blob("f", around: 0, count: 6, seed: 1)
        #expect(suggest(photos, [(candidate("Food"), Self.axis(0))]).isEmpty)
        let seven = Self.blob("f", around: 0, count: 7, seed: 1)
        #expect(!suggest(seven, [(candidate("Food"), Self.axis(0))]).isEmpty)
    }

    @Test func dropsClustersSmallerThan3() {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 10, seed: 1),
            Self.blob("p", around: 1, count: 10, seed: 2),
            Self.blob("c", around: 2, count: 2, seed: 3))
        let result = suggest(photos, [
            (candidate("Food"), Self.axis(0)), (candidate("Pets"), Self.axis(1)), (candidate("Cars"), Self.axis(2)),
        ])
        #expect(Set(result.map(\.name)) == ["Food", "Pets"])
        let ids = result.flatMap(\.ids)
        #expect(ids.count == 20)
        #expect(!ids.contains { $0.hasPrefix("c") })
        #expect(result.allSatisfy { $0.ids.count >= 3 })
    }

    @Test func skipsCandidatesThatMatchExistingCategories() {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 10, seed: 1),
            Self.blob("p", around: 1, count: 10, seed: 2))
        let meals = Candidate(displayName: "Meals", emoji: "🍽️", prompts: ["a photo of a meal"])
        let result = suggest(
            photos,
            [
                (candidate("Food", "🍔"), Self.axis(0)),
                (meals, Self.between(0, 6)),
                (candidate("Pets", "🐶"), Self.axis(1)),
            ],
            existing: ["FOOD"])
        let byName = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["Meals", "Pets"])
        #expect(byName["Meals"]?.emoji == "🍽️")
        #expect(byName["Meals"]?.prompts == ["a photo of a meal"])
        #expect(byName["Meals"]?.ids.allSatisfy { $0.hasPrefix("f") } == true)
        #expect(byName["Pets"]?.prompts == ["a photo of pets"])
    }

    @Test func mergesClustersWithTheSameCandidate() throws {
        let photos = Self.merged(
            Self.blob("x", around: 3, count: 10, seed: 1),
            Self.blob("y", around: 4, count: 10, seed: 2))
        let result = suggest(photos, [
            (candidate("Food"), Self.between(3, 4)),
            (candidate("Pets"), Self.axis(1)),
        ])
        try #require(result.map(\.name) == ["Food"])
        #expect(result[0].ids.count == 20)
        #expect(result[0].ids == result[0].ids.sorted())
    }

    /// Phase 12: a low score does not give a "Group <n>". The best candidate that is left names the cluster.
    @Test func lowScoreClusterStillGetsCandidateName() throws {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 12, seed: 1),
            Self.blob("g", around: 5, count: 10, seed: 2),
            Self.blob("h", around: 6, count: 8, seed: 3))
        // Cosine of "Workshop" with e5 is 0.1 and of "Seascape" with e6 is 0.1: both below minScore 0.22.
        let weak = { (a: Int) in VectorMath.normalize(zip(Self.axis(a), Self.axis(7)).map { 0.1 * $0 + 0.995 * $1 }) }
        let result = suggest(photos, [
            (candidate("Food"), Self.axis(0)), (candidate("Workshop"), weak(5)), (candidate("Seascape"), weak(6)),
        ])
        try #require(result.map(\.name) == ["Food", "Workshop", "Seascape"])
        #expect(result[1].prompts == ["a photo of workshop"])
        #expect(result[1].ids.allSatisfy { $0.hasPrefix("g") })
        #expect(result[2].ids.allSatisfy { $0.hasPrefix("h") })
        #expect(!result.contains { $0.emoji == SuggestionService.groupEmoji })
    }

    /// "Group <n>" only when every candidate name is taken. Group numbers skip existing names.
    @Test func groupNOnlyWhenNoCandidateLeft() throws {
        let photos = Self.merged(
            Self.blob("g", around: 5, count: 10, seed: 2),
            Self.blob("h", around: 6, count: 8, seed: 3))
        let named = suggest(photos, [(candidate("Food"), Self.axis(0))], existing: ["group 1"])
        try #require(named.map(\.name) == ["Food"])
        #expect(named[0].ids.count == 18)

        let result = suggest(photos, [(candidate("Food"), Self.axis(0))], existing: ["group 1", "FOOD"])
        try #require(result.map(\.name) == ["Group 2", "Group 3"])
        #expect(result.allSatisfy { $0.emoji == "📁" && $0.prompts.isEmpty })
        #expect(result[0].ids.allSatisfy { $0.hasPrefix("g") })
    }

    @Test func sortedBySizeLargestFirst() {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 15, seed: 1),
            Self.blob("p", around: 1, count: 8, seed: 2),
            Self.blob("c", around: 2, count: 11, seed: 3))
        let result = suggest(photos, [
            (candidate("Pets"), Self.axis(1)), (candidate("Food"), Self.axis(0)), (candidate("Cars"), Self.axis(2)),
        ])
        #expect(result.map(\.name) == ["Food", "Cars", "Pets"])
        #expect(result.map(\.ids.count) == [15, 11, 8])
    }

    @Test func sameInputGivesSameSuggestions() {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 15, seed: 1),
            Self.blob("g", around: 5, count: 9, seed: 2))
        let candidates = [(candidate("Food"), Self.axis(0))]
        let a = suggest(photos, candidates), b = suggest(photos, candidates)
        #expect(a.map(\.name) == b.map(\.name))
        #expect(a.map(\.ids) == b.map(\.ids))
    }

    @Test func skipsTwoTakenNamesInARow() {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 10, seed: 1),
            Self.blob("p", around: 1, count: 10, seed: 2))
        let snacks = VectorMath.normalize(zip(Self.axis(0), Self.axis(7)).map { $0 + 2 * $1 })  // cos 0.45 with e0.
        let result = suggest(
            photos,
            [
                (candidate("Food"), Self.axis(0)), (candidate("Meals"), Self.between(0, 6)),
                (candidate("Snacks"), snacks), (candidate("Pets"), Self.axis(1)),
            ],
            existing: ["food", "MEALS"])
        #expect(Set(result.map(\.name)) == ["Snacks", "Pets"])
        #expect(result.first { $0.name == "Snacks" }?.ids.allSatisfy { $0.hasPrefix("f") } == true)
    }

    /// The best candidate of the "p" cluster is taken. Its next best is the best of the "f" cluster,
    /// so the 2 clusters merge.
    @Test func nextBestThatIsAnotherClustersBestMerges() throws {
        let photos = Self.merged(
            Self.blob("f", around: 0, count: 10, seed: 1),
            Self.blob("p", around: 1, count: 10, seed: 2))
        let result = service.suggest(
            notSure: photos, candidates: [candidate("Food"), candidate("Pets")],
            candidateVectors: [[Self.axis(0), Self.between(1, 7)], [Self.axis(1)]],
            existingNames: ["Pets"], seed: 42)
        try #require(result.map(\.name) == ["Food"])
        #expect(result[0].ids.count == 20)
    }

    /// Fix round 1: an old session has a category with an old name of a merged or shortened entry.
    /// The entry counts as taken, so no suggestion repeats the category under its new name.
    @Test func aliasOfExistingCategoryCountsAsTaken() {
        let photos = Self.blob("s", around: 0, count: 10, seed: 1)
        let selfies = Candidate(displayName: "Selfies", emoji: "🤳", prompts: ["a selfie"], aliases: ["Selfie"])
        let result = suggest(photos, [(selfies, Self.axis(0)), (candidate("Portraits"), Self.between(0, 6))],
                             existing: ["SELFIE"])
        #expect(result.map(\.name) == ["Portraits"])
    }

    /// Phase 11: at least 20 "Not sure" photos and at least 10% of the images.
    @Test func manyNotSureRule() {
        #expect(SuggestionService.manyNotSure(notSure: 20, images: 200))
        #expect(!SuggestionService.manyNotSure(notSure: 19, images: 100))
        #expect(!SuggestionService.manyNotSure(notSure: 20, images: 201))
        #expect(SuggestionService.manyNotSure(notSure: 20, images: 20))
        #expect(!SuggestionService.manyNotSure(notSure: 0, images: 0))
    }
}
