import Foundation
import Testing
@testable import PicnestCore

typealias Category = PicnestCore.Category

struct ClassifyServiceTests {
    private let catA = Category(id: UUID(), displayName: "A", emoji: "A", prompts: ["a"], exampleIDs: [], order: 0)
    private let catB = Category(id: UUID(), displayName: "B", emoji: "B", prompts: ["b"], exampleIDs: [], order: 1)
    private let service = ClassifyService(settings: ClassifySettings(
        minScore: 0.22, minMargin: 0.02, temperature: 0.01, exampleScale: 1, exampleOffset: 0))

    private var prompts: [CategoryID: [Vector]] { [catA.id: [[1, 0, 0]], catB.id: [[0, 1, 0]]] }

    /// A unit vector whose cosines with e1 and e2 are `a` and `b`.
    private func photo(_ a: Float, _ b: Float) -> Vector { [a, b, (1 - a * a - b * b).squareRoot()] }

    private func assignment(_ states: [MediaID: PhotoState], _ id: MediaID) throws -> Assignment {
        guard case .auto(let a)? = states[id] else { throw Failure() }
        return a
    }
    private struct Failure: Error {}

    @Test func picksBestPrompt() throws {
        let out = service.classify(
            states: [:], categories: [catA, catB], images: ["x": photo(0.1, 0.8)], prompts: prompts)
        let a = try assignment(out, "x")
        #expect(a.categoryID == catB.id)
        #expect(a.secondCategoryID == catA.id)
        #expect(abs(a.score - 0.8) < 1e-5)
        #expect(abs((a.secondScore ?? 0) - 0.1) < 1e-5)
        #expect(a.percent == 100)
        #expect(!a.uncertain)
    }

    @Test func uncertainWhenLowScore() throws {
        let out = service.classify(
            states: [:], categories: [catA, catB], images: ["x": photo(0.21, 0.10)], prompts: prompts)
        #expect(try assignment(out, "x").uncertain)
    }

    @Test func uncertainWhenMarginSmall() throws {
        let close = service.classify(
            states: [:], categories: [catA, catB], images: ["x": photo(0.30, 0.29)], prompts: prompts)
        #expect(try assignment(close, "x").uncertain)
        let apart = service.classify(
            states: [:], categories: [catA, catB], images: ["x": photo(0.30, 0.20)], prompts: prompts)
        #expect(!(try assignment(apart, "x").uncertain))
    }

    @Test func manualStatesNeverChange() {
        let held = Assignment(categoryID: catB.id, score: 0.1, secondCategoryID: nil, secondScore: nil, percent: 50, uncertain: true)
        let states: [MediaID: PhotoState] = [
            "m": .manual(catB.id), "h": .heldNotSure(held), "d": .dontMove, "u": .unreadable,
        ]
        let images: [MediaID: Vector] = ["m": photo(0.9, 0), "h": photo(0.9, 0), "d": photo(0.9, 0)]
        let out = service.classify(states: states, categories: [catA, catB], images: images, prompts: prompts)
        #expect(out == states)
    }

    @Test func examplesPullSimilarPhotos() throws {
        // Prompt score for A is 0.1. Three example photos of A are close to the photo.
        var a = catA
        a.exampleIDs = ["e1", "e2", "e3"]
        let ex: Vector = [0.1, 0.1, 0.9899495]
        var images: [MediaID: Vector] = ["x": photo(0.1, 0.15)]
        for id in a.exampleIDs { images[id] = ex }
        let without = service.classify(states: [:], categories: [catA, catB], images: ["x": images["x"]!], prompts: prompts)
        #expect(try assignment(without, "x").categoryID == catB.id)
        let out = service.classify(states: [:], categories: [a, catB], images: images, prompts: prompts)
        let r = try assignment(out, "x")
        #expect(r.categoryID == a.id)
        #expect(r.score > 0.9)
    }

    @Test func photoIsNotItsOwnExample() throws {
        var a = catA
        a.exampleIDs = ["x"]
        let out = service.classify(states: [:], categories: [a, catB], images: ["x": photo(0.1, 0.5)], prompts: prompts)
        let r = try assignment(out, "x")
        #expect(r.categoryID == catB.id)
        #expect(abs((r.secondScore ?? 0) - 0.1) < 1e-5)  // Own similarity 1.0 is not used.
    }

    @Test func noCategories() {
        let states: [MediaID: PhotoState] = [
            "a": .auto(Assignment(categoryID: catA.id, score: 1, secondCategoryID: nil, secondScore: nil, percent: 100, uncertain: false)),
            "d": .dontMove,
        ]
        let out = service.classify(states: states, categories: [], images: ["a": [1, 0, 0], "n": [0, 1, 0]], prompts: [:])
        #expect(out == ["d": .dontMove])
    }

    @Test func singleCategory() throws {
        let out = service.classify(states: [:], categories: [catA], images: ["x": photo(0.5, 0)], prompts: prompts)
        let a = try assignment(out, "x")
        #expect(a.secondCategoryID == nil && a.percent == 100 && !a.uncertain)
    }

    @Test(.enabled(if: BuildConfig.isRelease, "Run with -c release"))
    func recalculationIsFast() {
        var rng = SplitMix64(seed: 5)
        func random() -> Vector {
            VectorMath.normalize((0..<512).map { _ in Float.random(in: -1...1, using: &rng) })
        }
        var images: [MediaID: Vector] = [:]
        for i in 0..<5000 { images["p\(i)"] = random() }
        var categories: [Category] = []
        var prompts: [CategoryID: [Vector]] = [:]
        for c in 0..<10 {
            let cat = Category(
                id: UUID(), displayName: "C\(c)", emoji: "", prompts: ["p"],
                exampleIDs: (0..<500).map { "p\(c * 500 + $0)" }, order: c)
            categories.append(cat)
            prompts[cat.id] = (0..<3).map { _ in random() }
        }
        // Probe: far from every prompt, very close to the examples of category 3 (not an example itself).
        let base = images["p1500"]!  // First example of category 3.
        var noise = random()
        noise = VectorMath.normalize(zip(base, noise).map { $0 + 0.05 * $1 })
        images["probe"] = noise
        for id in categories[3].exampleIDs.prefix(10) {
            images[id] = VectorMath.normalize(zip(base, images[id]!).map { $0 + 0.05 * $1 })
        }
        images["probe"] = VectorMath.normalize(zip(base, noise).map { $0 + $1 })
        let start = ContinuousClock.now
        let out = service.classify(states: [:], categories: categories, images: images, prompts: prompts)
        let elapsed = ContinuousClock.now - start
        print("classify 5000 photos: \(elapsed)")
        #expect(out.count == 5001)
        if case .auto(let probe)? = out["probe"] {
            #expect(probe.categoryID == categories[3].id)
            #expect(probe.score > 0.9)
        } else { Issue.record("no probe state") }
        // An example is classified through its other examples (self excluded: score < 1).
        if case .auto(let ex)? = out["p1500"] {
            #expect(ex.categoryID == categories[3].id)
            #expect(ex.score < 0.999 && ex.score > 0.9)
        } else { Issue.record("no example state") }
        #expect(elapsed < .seconds(2))
    }


    @Test func secondPercentFollowsTheScoreGap() {
        // softmax: p2 / p1 = exp((s2 - s1) / T). With T = 0.01, a gap of 0.01 * ln(38 / 41) gives 41 → 38.
        let s1: Float = 0.30
        let s2 = s1 + 0.01 * Float(log(38.0 / 41.0))
        let a = Assignment(categoryID: catA.id, score: s1, secondCategoryID: catB.id, secondScore: s2,
                           percent: 41, uncertain: true)
        #expect(service.secondPercent(of: a) == 38)
        let none = Assignment(categoryID: catA.id, score: s1, secondCategoryID: nil, secondScore: nil,
                              percent: 100, uncertain: false)
        #expect(service.secondPercent(of: none) == nil)
    }
}
