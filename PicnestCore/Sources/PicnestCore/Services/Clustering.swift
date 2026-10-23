import Foundation

/// A small seeded random number generator, so that clustering gives the same result for a seed.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Spherical k-means with cosine distance (spec 4.3). Inputs are normalized first.
public enum Clustering {
    static let maxIterations = 50
    static let defaultSampleLimit = 2000
    /// Distances at or below this value count as zero (identical points).
    private static let epsilon: Float = 1e-6

    /// The k values to test for `n` photos. Returns nil for fewer than 7 photos (1 category, or none).
    /// 42 photos or more: 6...14, capped at `n - 1`. 7 to 41 photos: 2...max(2, min(14, n / 7)).
    public static func kRange(for n: Int) -> ClosedRange<Int>? {
        guard n >= 7 else { return nil }
        if n >= 42 { return 6...min(14, n - 1) }
        return 2...max(2, min(14, n / 7))
    }

    /// Returns a label in `0..<m` for each vector, with `m <= k`. Labels are numbered in order of
    /// first appearance. `m` is smaller than `k` when there are fewer distinct points than `k`.
    public static func kMeans(_ v: [Vector], k: Int, seed: UInt64) -> [Int] {
        guard !v.isEmpty else { return [] }
        guard k > 1 else { return Array(repeating: 0, count: v.count) }
        let points = v.map(VectorMath.normalize)
        var rng = SplitMix64(seed: seed)
        var centers = initialCenters(points, k: k, rng: &rng)
        var labels = [Int](repeating: -1, count: points.count)

        for _ in 0..<maxIterations {
            let (newLabels, distances) = assign(points, centers: centers)
            var assigned = newLabels
            reseedEmptyClusters(&assigned, distances: distances, clusterCount: centers.count)
            if assigned == labels { break }
            labels = assigned
            centers = updatedCenters(points, labels: labels, old: centers)
        }
        return compact(labels)
    }

    /// Mean silhouette score with cosine distance, over at most `sampleLimit` random points.
    /// Returns 0 when there are fewer than 2 clusters.
    public static func silhouette(_ v: [Vector], labels: [Int], sampleLimit: Int, seed: UInt64) -> Float {
        let n = v.count
        guard n > 1, labels.count == n else { return 0 }
        let clusterCount = (labels.max() ?? 0) + 1
        guard Set(labels).count > 1 else { return 0 }
        let points = v.map(VectorMath.normalize)
        var sizes = [Int](repeating: 0, count: clusterCount)
        for l in labels { sizes[l] += 1 }

        var sample = Array(0..<n)
        if n > sampleLimit {
            var rng = SplitMix64(seed: seed)
            sample.shuffle(using: &rng)
            sample = Array(sample.prefix(max(sampleLimit, 1)))
        }

        var total: Float = 0
        let chunk = 256
        for start in stride(from: 0, to: sample.count, by: chunk) {
            let rows = Array(sample[start..<min(start + chunk, sample.count)])
            let cosines = VectorMath.matmul(rows.map { points[$0] }, points)
            for (r, i) in rows.enumerated() {
                let own = labels[i]
                guard sizes[own] > 1 else { continue }  // A single-point cluster scores 0.
                var sums = [Float](repeating: 0, count: clusterCount)
                for (j, c) in cosines[r].enumerated() where j != i {
                    sums[labels[j]] += max(0, 1 - c)
                }
                let a = sums[own] / Float(sizes[own] - 1)
                var b = Float.greatestFiniteMagnitude
                for c in 0..<clusterCount where c != own && sizes[c] > 0 {
                    b = min(b, sums[c] / Float(sizes[c]))
                }
                let denom = max(a, b)
                if denom > 0 { total += (b - a) / denom }
            }
        }
        return total / Float(sample.count)
    }

    /// Runs k-means for each k in `range` (limited to `count - 1`) and keeps the best silhouette.
    /// Fewer than `range.lowerBound + 1` photos (7 for 6...14) give 1 cluster. No photos give k 0.
    /// `k` is the number of clusters in the result, which can be less than the k that was tried.
    public static func bestK(_ v: [Vector], range: ClosedRange<Int>, seed: UInt64) -> (k: Int, labels: [Int]) {
        guard !v.isEmpty else { return (0, []) }
        guard v.count > max(range.lowerBound, 1) else { return (1, Array(repeating: 0, count: v.count)) }
        let upper = min(range.upperBound, v.count - 1)
        let lower = max(range.lowerBound, 2)
        guard lower <= upper else { return (1, Array(repeating: 0, count: v.count)) }

        var best: (score: Float, labels: [Int])?
        for k in lower...upper {
            let labels = kMeans(v, k: k, seed: seed)
            let score = silhouette(v, labels: labels, sampleLimit: defaultSampleLimit, seed: seed)
            if best == nil || score > best!.score { best = (score, labels) }
        }
        let labels = best?.labels ?? Array(repeating: 0, count: v.count)
        return (Set(labels).count, labels)
    }

    // MARK: - Cluster naming (shared by the scan and the suggestions)

    /// The normalized mean of the normalized members of each cluster in `0..<k`, and the size of each
    /// cluster. An empty cluster has a zero center.
    static func centers(_ v: [Vector], labels: [Int], k: Int) -> (centers: [Vector], sizes: [Int]) {
        guard let dim = v.first?.count else { return (Array(repeating: [], count: k), Array(repeating: 0, count: k)) }
        var sums = Array(repeating: Vector(repeating: 0, count: dim), count: k)
        var sizes = [Int](repeating: 0, count: k)
        for (vector, label) in zip(v, labels) {
            sizes[label] += 1
            let unit = VectorMath.normalize(vector)
            for d in 0..<dim { sums[label][d] += unit[d] }
        }
        return (sums.map(VectorMath.normalize), sizes)
    }

    /// `scores[cluster][candidate]`: the highest cosine between the cluster center and a prompt of the
    /// candidate. `promptVectors[candidate]` holds the normalized prompt vectors of each candidate.
    /// A candidate with no prompts scores `-greatestFiniteMagnitude`.
    static func candidateScores(centers: [Vector], promptVectors: [[Vector]]) -> [[Float]] {
        let flat = promptVectors.flatMap { $0 }
        var owner: [Int] = []  // Candidate index of each prompt.
        for (index, prompts) in promptVectors.enumerated() { owner += Array(repeating: index, count: prompts.count) }
        let cosines = flat.isEmpty ? centers.map { _ in [Float]() } : VectorMath.matmul(centers, flat)
        return cosines.map { row in
            var scores = [Float](repeating: -.greatestFiniteMagnitude, count: promptVectors.count)
            for (p, c) in row.enumerated() { scores[owner[p]] = max(scores[owner[p]], c) }
            return scores
        }
    }

    /// The index of the highest score among the allowed candidates (the first one on a tie), or nil
    /// when no candidate is allowed.
    static func bestCandidate(_ scores: [Float], allowed: (Int) -> Bool = { _ in true }) -> Int? {
        var best: Int?
        for i in scores.indices where allowed(i) {
            if best == nil || scores[i] > scores[best!] { best = i }
        }
        return best
    }

    // MARK: - Steps

    /// k-means++: the first center is random, then each next center is picked with probability
    /// proportional to the squared distance to the nearest center. Stops early when all points
    /// sit on a center already.
    private static func initialCenters(_ points: [Vector], k: Int, rng: inout SplitMix64) -> [Vector] {
        var centers = [points[Int.random(in: 0..<points.count, using: &rng)]]
        var nearest = VectorMath.matmul(points, centers).map { max(0, 1 - $0[0]) }
        while centers.count < k {
            let weights = nearest.map { $0 * $0 }
            let sum = weights.reduce(0, +)
            guard sum > epsilon * epsilon else { break }
            var target = Float.random(in: 0..<sum, using: &rng)
            var pick = weights.count - 1
            for (i, w) in weights.enumerated() {
                if target < w { pick = i; break }
                target -= w
            }
            if weights[pick] <= 0 { pick = weights.indices.max { weights[$0] < weights[$1] }! }
            centers.append(points[pick])
            let toNew = VectorMath.matmul(points, [points[pick]]).map { max(0, 1 - $0[0]) }
            for i in nearest.indices { nearest[i] = min(nearest[i], toNew[i]) }
        }
        return centers
    }

    /// Nearest center for each point (the first one on a tie), and the distance to it.
    private static func assign(_ points: [Vector], centers: [Vector]) -> (labels: [Int], distances: [Float]) {
        let cosines = VectorMath.matmul(points, centers)
        var labels = [Int](repeating: 0, count: points.count)
        var distances = [Float](repeating: 0, count: points.count)
        for (i, row) in cosines.enumerated() {
            var bestIndex = 0
            for c in 1..<row.count where row[c] > row[bestIndex] { bestIndex = c }
            labels[i] = bestIndex
            distances[i] = max(0, 1 - row[bestIndex])
        }
        return (labels, distances)
    }

    /// Moves the farthest point into each empty cluster. A cluster stays empty when no point is
    /// farther than `epsilon` from its center (there are not enough distinct points).
    private static func reseedEmptyClusters(_ labels: inout [Int], distances: [Float], clusterCount: Int) {
        var sizes = [Int](repeating: 0, count: clusterCount)
        for l in labels { sizes[l] += 1 }
        var used = Set<Int>()
        for c in 0..<clusterCount where sizes[c] == 0 {
            var far: Int?
            for i in labels.indices where !used.contains(i) && sizes[labels[i]] > 1 && distances[i] > epsilon {
                if far == nil || distances[i] > distances[far!] { far = i }
            }
            guard let i = far else { continue }
            used.insert(i)
            sizes[labels[i]] -= 1
            labels[i] = c
            sizes[c] = 1
        }
    }

    /// Normalized mean of the members of each cluster. An empty cluster keeps its old center.
    private static func updatedCenters(_ points: [Vector], labels: [Int], old: [Vector]) -> [Vector] {
        let dim = points[0].count
        var sums = Array(repeating: Vector(repeating: 0, count: dim), count: old.count)
        var counts = [Int](repeating: 0, count: old.count)
        for (p, l) in zip(points, labels) {
            counts[l] += 1
            for d in 0..<dim { sums[l][d] += p[d] }
        }
        return (0..<old.count).map { counts[$0] > 0 ? VectorMath.normalize(sums[$0]) : old[$0] }
    }

    /// Renumbers labels to `0..<m` in order of first appearance.
    private static func compact(_ labels: [Int]) -> [Int] {
        var map: [Int: Int] = [:]
        return labels.map { l in
            if let m = map[l] { return m }
            map[l] = map.count
            return map[l]!
        }
    }
}
