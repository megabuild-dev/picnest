import Foundation

/// Suggests new categories for the "Not sure" photos (spec 4.8). Pure: no I/O.
public struct SuggestionService: Sendable {
    /// Fewer "Not sure" photos than this give no suggestion (spec 4.8 step 1).
    public static let minimumPhotos = 7
    /// A cluster with fewer photos than this is dropped (spec 4.8 step 3, spec 14).
    public static let minimumPhotosPerSuggestion = 3
    public static let groupEmoji = "📁"

    /// At least this many "Not sure" photos are "many" (spec 3.5, 3.7).
    public static let manyNotSureMinimum = 20

    public init() {}

    /// The 1 rule for "many Not sure photos" (spec 3.5, 3.7): at least 20 "Not sure" photos, and at least
    /// 10% of `images` (the images that are not trashed). The Sort sheet hint and the sheet after a scan use it.
    public static func manyNotSure(notSure: Int, images: Int) -> Bool {
        notSure >= manyNotSureMinimum && notSure * 10 >= images
    }

    /// Spec 4.8 steps 1 to 6.
    /// - Parameters:
    ///   - notSure: the vectors of the "Not sure" photos.
    ///   - candidateVectors: the prompt vectors of each candidate, in the order of `candidates`.
    ///   - existingNames: the names of the categories that exist now. Compared case-insensitively with the
    ///     name and the aliases of each candidate.
    /// - Returns: the suggestions, largest first. Each name is unique against `existingNames` and the
    ///   other suggestions (case-insensitive).
    public func suggest(
        notSure: [MediaID: Vector], candidates: [Candidate], candidateVectors: [[Vector]],
        existingNames: Set<String>, seed: UInt64
    ) -> [CategorySuggestion] {
        // Step 1. Sorted ids make the result the same for the same input.
        let ids = notSure.keys.sorted()
        guard ids.count >= Self.minimumPhotos, let range = Clustering.kRange(for: ids.count) else { return [] }
        let vectors = ids.map { notSure[$0]! }

        // Step 2.
        let (k, labels) = Clustering.bestK(vectors, range: range, seed: seed)
        let (centers, sizes) = Clustering.centers(vectors, labels: labels, k: k)
        var members = Array(repeating: [MediaID](), count: k)
        for (id, label) in zip(ids, labels) { members[label].append(id) }

        // Step 3.
        let kept = (0..<k).filter { sizes[$0] >= Self.minimumPhotosPerSuggestion }
        guard !kept.isEmpty else { return [] }

        // Steps 4 and 5. Skip candidates whose name or alias is taken. The best candidate that is left names the
        // cluster, whatever its score (phase 12). Only a cluster with no candidate left gets a "Group <n>".
        let taken = Set(existingNames.map { $0.lowercased() })
        let promptVectors = candidates.indices.map { i in
            (i < candidateVectors.count ? candidateVectors[i] : []).map(VectorMath.normalize)
        }
        let scores = Clustering.candidateScores(centers: kept.map { centers[$0] }, promptVectors: promptVectors)

        var named: [String: (candidate: Candidate, ids: [MediaID], first: Int)] = [:]  // Key: lowercased name.
        var groups: [(ids: [MediaID], first: Int)] = []
        for (row, cluster) in kept.enumerated() {
            let best = Clustering.bestCandidate(scores[row]) {
                // Taken when its name or an old name (alias) is an existing category name.
                !candidates[$0].names.contains { taken.contains($0.lowercased()) } && !promptVectors[$0].isEmpty
            }
            if let best {
                let key = candidates[best].displayName.lowercased()
                if let existing = named[key] {
                    named[key] = (existing.candidate, existing.ids + members[cluster], existing.first)
                } else {
                    named[key] = (candidates[best], members[cluster], cluster)
                }
            } else {
                groups.append((members[cluster], cluster))
            }
        }

        // Step 6. Ties keep the cluster order. Groups are numbered in the final order.
        enum Kind { case candidate(Candidate), group }
        let all: [(kind: Kind, ids: [MediaID], first: Int)] =
            named.values.map { (.candidate($0.candidate), $0.ids, $0.first) } + groups.map { (.group, $0.ids, $0.first) }
        let ordered = all.sorted { $0.ids.count != $1.ids.count ? $0.ids.count > $1.ids.count : $0.first < $1.first }

        var used = taken.union(named.keys)
        var groupNumber = 0
        return ordered.map { item in
            switch item.kind {
            case .candidate(let c):
                return CategorySuggestion(name: c.displayName, emoji: c.emoji, prompts: c.prompts, ids: item.ids.sorted())
            case .group:
                var name: String
                repeat {
                    groupNumber += 1
                    name = "Group \(groupNumber)"
                } while used.contains(name.lowercased())
                used.insert(name.lowercased())
                return CategorySuggestion(name: name, emoji: Self.groupEmoji, prompts: [], ids: item.ids.sorted())
            }
        }
    }
}
