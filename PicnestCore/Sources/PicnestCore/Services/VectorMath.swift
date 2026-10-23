import Accelerate
import Foundation

public enum VectorMath {
    public static func dot(_ a: Vector, _ b: Vector) -> Float {
        vDSP.dot(a, b)
    }

    /// Returns `v` scaled to length 1. A zero vector stays zero.
    public static func normalize(_ v: Vector) -> Vector {
        let norm = vDSP.dot(v, v).squareRoot()
        guard norm > 0 else { return v }
        return vDSP.divide(v, norm)
    }

    /// Returns `a.count x bT.count` dot products. Each row of `bT` is one vector (B transposed).
    /// For unit vectors the values are cosines.
    public static func matmul(_ a: [Vector], _ bT: [Vector]) -> [[Float]] {
        guard !a.isEmpty else { return [] }
        guard !bT.isEmpty else { return Array(repeating: [], count: a.count) }
        let m = a.count, n = bT.count, k = a[0].count
        let aFlat = a.flatMap { $0 }
        let bFlat = bT.flatMap { $0 }
        var c = [Float](repeating: 0, count: m * n)
        // C (m x n) = A (m x k) * B^T, where bT is stored row-major n x k.
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(m), Int32(n), Int32(k),
                    1, aFlat, Int32(k), bFlat, Int32(k), 0, &c, Int32(n))
        return (0..<m).map { Array(c[($0 * n)..<(($0 + 1) * n)]) }
    }

    public static func softmax(_ x: [Float], temperature: Float) -> [Float] {
        guard let maxValue = x.max() else { return [] }
        let exps = x.map { Foundation.exp(($0 - maxValue) / temperature) }
        let sum = exps.reduce(0, +)
        return exps.map { $0 / sum }
    }

    /// Example score of `image` (spec 4.4): the mean of the 3 highest cosines to `examples`.
    /// With fewer than 3 examples, the mean of all of them. Returns nil without examples.
    /// All vectors must be unit vectors, and `examples` must not contain `image` itself.
    public static func exampleScore(image: Vector, examples: [Vector]) -> Float? {
        exampleScore(similarities: matmul([image], examples)[0])
    }

    /// Core of the example score: the mean of the 3 highest values of `similarities`
    /// (all of them when fewer than 3). Returns nil when empty.
    public static func exampleScore(similarities: some Sequence<Float>) -> Float? {
        var top: (Float, Float, Float) = (-.infinity, -.infinity, -.infinity)
        var count = 0
        for s in similarities {
            count += 1
            if s > top.0 { top = (s, top.0, top.1) } else if s > top.1 { top = (top.0, s, top.1) } else if s > top.2 { top.2 = s }
        }
        guard count > 0 else { return nil }
        let n = min(count, 3)
        return ([top.0, top.1, top.2].prefix(n).reduce(0, +)) / Float(n)
    }
}
