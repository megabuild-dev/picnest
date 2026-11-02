import Foundation

public struct ClassifySettings: Codable, Sendable, Hashable {
    public var minScore: Float
    public var minMargin: Float
    public var temperature: Float
    public var exampleScale: Float
    public var exampleOffset: Float
    /// The lowest cosine of 2 image embeddings that makes them similar photos (spec 4.9).
    public var duplicateSimilarity: Float

    public static let defaultDuplicateSimilarity: Float = 0.95

    public init(
        minScore: Float, minMargin: Float, temperature: Float, exampleScale: Float, exampleOffset: Float,
        duplicateSimilarity: Float = ClassifySettings.defaultDuplicateSimilarity
    ) {
        self.minScore = minScore
        self.minMargin = minMargin
        self.temperature = temperature
        self.exampleScale = exampleScale
        self.exampleOffset = exampleOffset
        self.duplicateSimilarity = duplicateSimilarity
    }

    private enum CodingKeys: String, CodingKey {
        case minScore, minMargin, temperature, exampleScale, exampleOffset, duplicateSimilarity
    }

    /// Settings saved before the Duplicates view have no `duplicateSimilarity`. They get the default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minScore = try c.decode(Float.self, forKey: .minScore)
        minMargin = try c.decode(Float.self, forKey: .minMargin)
        temperature = try c.decode(Float.self, forKey: .temperature)
        exampleScale = try c.decode(Float.self, forKey: .exampleScale)
        exampleOffset = try c.decode(Float.self, forKey: .exampleOffset)
        duplicateSimilarity = try c.decodeIfPresent(Float.self, forKey: .duplicateSimilarity)
            ?? Self.defaultDuplicateSimilarity
    }

    /// Placeholder values. Task 4 replaces them with measured values. `duplicateSimilarity` is provisional.
    public static let `default` = ClassifySettings(
        minScore: 0.22, minMargin: 0.02, temperature: 0.01, exampleScale: 1.0, exampleOffset: 0.0)
}

public struct Assignment: Codable, Sendable, Hashable {
    public var categoryID: CategoryID
    public var score: Float
    public var secondCategoryID: CategoryID?
    public var secondScore: Float?
    public var percent: Int
    public var uncertain: Bool

    public init(categoryID: CategoryID, score: Float, secondCategoryID: CategoryID?, secondScore: Float?, percent: Int, uncertain: Bool) {
        self.categoryID = categoryID
        self.score = score
        self.secondCategoryID = secondCategoryID
        self.secondScore = secondScore
        self.percent = percent
        self.uncertain = uncertain
    }

    /// True when the best score is below `settings.minScore`: the first branch of the uncertain rule
    /// (`ClassifyService`). A placeholder is not a weak match. `percent` does not decide this: it is a
    /// softmax share, so a photo can have a high percent and still a low score.
    public func isWeakMatch(settings: ClassifySettings) -> Bool {
        !isPlaceholder && score < settings.minScore
    }

    /// True for the guess of a photo that has no score at all: the first category, with score 0 and percent 0
    /// (a photo without an image vector, after its category was deleted).
    public var isPlaceholder: Bool {
        score == 0 && percent == 0 && secondCategoryID == nil
    }

    public func with(uncertain: Bool) -> Assignment {
        var copy = self
        copy.uncertain = uncertain
        return copy
    }
}

public enum PhotoState: Codable, Sendable, Hashable {
    case auto(Assignment)
    case manual(CategoryID)
    case heldNotSure(Assignment)
    case dontMove
    case unreadable

    public var isNotSure: Bool {
        switch self {
        case .heldNotSure: true
        case .auto(let a): a.uncertain
        default: false
        }
    }

    public var isManual: Bool {
        if case .manual = self { true } else { false }
    }
}
