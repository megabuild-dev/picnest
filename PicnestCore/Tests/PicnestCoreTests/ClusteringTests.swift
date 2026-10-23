import Foundation
import Testing
@testable import PicnestCore

struct ClusteringTests {
    /// `perGroup` noisy unit vectors around each of the first `groups` axes of a `dim`-space.
    private func blobs(groups: Int, perGroup: Int, dim: Int, noise: Float, seed: UInt64) -> [Vector] {
        var rng = SplitMix64(seed: seed)
        var out: [Vector] = []
        for g in 0..<groups {
            for _ in 0..<perGroup {
                var v = Vector(repeating: 0, count: dim)
                v[g] = 1
                for d in 0..<dim { v[d] += Float.random(in: -noise...noise, using: &rng) }
                out.append(VectorMath.normalize(v))
            }
        }
        return out
    }

    /// True when the labels split the input into the same groups as consecutive runs of `perGroup`.
    private func matchesGroups(_ labels: [Int], groups: Int, perGroup: Int) -> Bool {
        var seen = Set<Int>()
        for g in 0..<groups {
            let slice = Set(labels[(g * perGroup)..<((g + 1) * perGroup)])
            guard slice.count == 1, let label = slice.first, !seen.contains(label) else { return false }
            seen.insert(label)
        }
        return true
    }

    @Test func kMeansSeparatesThreeBlobs() {
        let v = blobs(groups: 3, perGroup: 20, dim: 8, noise: 0.1, seed: 1)
        let labels = Clustering.kMeans(v, k: 3, seed: 42)
        #expect(labels.count == 60)
        #expect(Set(labels).count == 3)
        #expect(matchesGroups(labels, groups: 3, perGroup: 20))
    }

    @Test func kMeansIsDeterministicForASeed() {
        let v = blobs(groups: 4, perGroup: 15, dim: 8, noise: 0.4, seed: 7)
        #expect(Clustering.kMeans(v, k: 5, seed: 9) == Clustering.kMeans(v, k: 5, seed: 9))
    }

    @Test func kMeansNeverMakesMoreClustersThanDistinctPoints() {
        let a: Vector = [1, 0, 0], b: Vector = [0, 1, 0]
        let v = Array(repeating: a, count: 5) + Array(repeating: b, count: 3)
        let labels = Clustering.kMeans(v, k: 6, seed: 42)
        #expect(Set(labels) == [0, 1])
        #expect(matchesGroups(Array(labels.prefix(5)), groups: 1, perGroup: 5))
        #expect(Set(labels.prefix(5)).isDisjoint(with: labels.suffix(3)))
    }

    @Test func bestKFindsSixOnSixBlobs() {
        let v = blobs(groups: 6, perGroup: 10, dim: 10, noise: 0.1, seed: 3)
        // A range that starts below 6 makes the result a real choice.
        let narrow = Clustering.bestK(v, range: 3...10, seed: 42)
        #expect(narrow.k == 6)
        #expect(matchesGroups(narrow.labels, groups: 6, perGroup: 10))
        #expect(Clustering.bestK(v, range: 6...14, seed: 42).k == 6)
    }

    @Test func silhouetteIsHighForCleanSplitAndLowForRandomLabels() {
        let v = blobs(groups: 3, perGroup: 20, dim: 8, noise: 0.1, seed: 5)
        let good = (0..<60).map { $0 / 20 }
        let bad = (0..<60).map { $0 % 3 }
        let sGood = Clustering.silhouette(v, labels: good, sampleLimit: 2000, seed: 42)
        let sBad = Clustering.silhouette(v, labels: bad, sampleLimit: 2000, seed: 42)
        #expect(sGood > 0.8)
        #expect(sBad < 0.1)
        let sampled = Clustering.silhouette(v, labels: good, sampleLimit: 10, seed: 42)
        #expect(sampled > 0.8)
    }

    @Test func bestKSmallInputs() {
        #expect(Clustering.bestK([], range: 6...14, seed: 42).k == 0)
        #expect(Clustering.bestK([], range: 6...14, seed: 42).labels.isEmpty)
        let six = blobs(groups: 6, perGroup: 1, dim: 8, noise: 0, seed: 1)
        let r = Clustering.bestK(six, range: 6...14, seed: 42)
        #expect(r.k == 1)
        #expect(r.labels == Array(repeating: 0, count: 6))
    }

    @Test func kRangeDependsOnPhotoCount() {
        #expect(Clustering.kRange(for: 0) == nil)
        #expect(Clustering.kRange(for: 6) == nil)
        #expect(Clustering.kRange(for: 7) == 2...2)
        #expect(Clustering.kRange(for: 13) == 2...2)
        #expect(Clustering.kRange(for: 41) == 2...5)
        #expect(Clustering.kRange(for: 42) == 6...14)
        #expect(Clustering.kRange(for: 100) == 6...14)
        #expect(Clustering.kRange(for: 10_000) == 6...14)
    }
}
