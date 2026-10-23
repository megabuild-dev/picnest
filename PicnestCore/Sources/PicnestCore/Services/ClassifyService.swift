import Foundation

/// Assigns photos to categories by prompt and example similarity (spec 4.4 to 4.6).
public struct ClassifyService: Sendable {
    public let settings: ClassifySettings

    public init(settings: ClassifySettings = .default) {
        self.settings = settings
    }

    /// Recalculates `.auto` states and creates states for photos in `images` that have none.
    /// Other states are kept. With no categories, `.auto` states are removed.
    public func classify(
        states: [MediaID: PhotoState], categories: [Category], images: [MediaID: Vector],
        prompts: [CategoryID: [Vector]]
    ) -> [MediaID: PhotoState] {
        var result = states
        if categories.isEmpty {
            for (id, state) in states { if case .auto = state { result[id] = nil } }
            return result
        }

        let ids = images.keys.filter { id in
            switch states[id] {
            case nil, .auto?: true
            default: false
            }
        }.sorted()
        guard !ids.isEmpty else { return result }

        // Prompt vectors of all categories in one list; each category owns a column range.
        var promptList: [Vector] = []
        var promptRange: [Range<Int>] = []
        for category in categories {
            let own = (prompts[category.id] ?? []).map(VectorMath.normalize)
            promptRange.append(promptList.count..<(promptList.count + own.count))
            promptList += own
        }
        // Example vectors, each photo once; each category lists its columns.
        var exampleColumn: [MediaID: Int] = [:]
        var exampleList: [Vector] = []
        var exampleIDs: [MediaID] = []
        var categoryExamples: [[Int]] = []
        for category in categories {
            var columns: [Int] = []
            for id in category.exampleIDs {
                guard let vector = images[id] else { continue }
                if exampleColumn[id] == nil {
                    exampleColumn[id] = exampleList.count
                    exampleList.append(VectorMath.normalize(vector))
                    exampleIDs.append(id)
                }
                columns.append(exampleColumn[id]!)
            }
            categoryExamples.append(columns)
        }

        let chunkSize = 256
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[start..<min(start + chunkSize, ids.count)])
            let vectors = chunk.map { VectorMath.normalize(images[$0]!) }
            let promptSims = VectorMath.matmul(vectors, promptList)
            let exampleSims = exampleList.isEmpty ? [] : VectorMath.matmul(vectors, exampleList)

            for (row, id) in chunk.enumerated() {
                let own = exampleColumn[id]
                var scores = [Float](repeating: 0, count: categories.count)
                for c in categories.indices {
                    var score: Float = -1
                    if !promptRange[c].isEmpty { score = promptSims[row][promptRange[c]].max()! }
                    let columns = categoryExamples[c].lazy.filter { $0 != own }
                    if !exampleList.isEmpty,
                       let e = VectorMath.exampleScore(similarities: columns.map { exampleSims[row][$0] }) {
                        score = max(score, settings.exampleScale * e + settings.exampleOffset)
                    }
                    scores[c] = score
                }
                result[id] = .auto(assignment(scores: scores, categories: categories))
            }
        }
        return result
    }

    /// The percent of the second guess, or nil if there is none (spec 3.3: "or Documents 38%").
    /// The softmax gives p2 / p1 = exp((s2 - s1) / temperature), and `percent` holds p1.
    public func secondPercent(of a: Assignment) -> Int? {
        guard a.secondCategoryID != nil, let second = a.secondScore else { return nil }
        let ratio = exp(Double(second - a.score) / Double(settings.temperature))
        return Int((Double(a.percent) * ratio).rounded())
    }

    private func assignment(scores: [Float], categories: [Category]) -> Assignment {
        var best = 0
        for i in 1..<scores.count where scores[i] > scores[best] { best = i }
        var second: Int?
        for i in scores.indices where i != best && (second == nil || scores[i] > scores[second!]) { second = i }
        let bestScore = scores[best]
        let margin = bestScore - (second.map { scores[$0] } ?? 0)
        let percent = Int((VectorMath.softmax(scores, temperature: settings.temperature)[best] * 100).rounded())
        return Assignment(
            categoryID: categories[best].id, score: bestScore,
            secondCategoryID: second.map { categories[$0].id }, secondScore: second.map { scores[$0] },
            percent: percent, uncertain: bestScore < settings.minScore || margin < settings.minMargin)
    }
}
