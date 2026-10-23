import Foundation

/// Finds exact and similar duplicate groups and their best photo (spec 4.9, 14). Pure: the caller
/// reads the files (hashes, pixel sizes) first, and only a user action trashes a photo.
public struct DuplicateService: Sendable {
    /// The rows of 1 matrix multiply in the similar search (spec 4.9).
    public static let blockSize = 1000

    public init() {}

    /// The duplicate groups of the images of `media`: exact groups first, then similar groups.
    ///
    /// - Exact: same size and same hash.
    /// - Similar: cosine of the vectors ≥ `similarity`. The similar search uses every photo outside the
    ///   exact groups and only the Keep photo of each exact group (spec 14). So a similar group never holds
    ///   2 photos of 1 exact group, but an exact Keep photo can also be in 1 similar group. There it is a
    ///   Keep photo too, so a similar group can have 2 or more Keep photos.
    ///   Similar pairs join into groups. Then each group keeps only the photos similar to its Keep photo,
    ///   and the other photos make new groups with the same rule (spec 4.9). A group of 1 is dropped.
    /// - Videos, and photos with no hash (no exact group) or no vector (no similar group), are left out.
    ///   The caller leaves out trashed, unreadable, and missing photos.
    /// - `ids` are best photo first: most pixels, largest file, oldest date (`dates`, else the
    ///   modification time), shortest relative path. The best photo is a Keep photo.
    /// - A group whose key is in `dismissed` is not returned.
    public func groups(
        media: [MediaFile], hashes: [MediaID: String], vectors: [MediaID: Vector], pixels: [MediaID: Int],
        dates: [MediaID: Date], similarity: Float, dismissed: Set<String>
    ) -> [DuplicateGroup] {
        var seen = Set<MediaID>()
        let images = media.filter { $0.kind == .image && seen.insert($0.id).inserted }

        func isBetter(_ a: MediaFile, _ b: MediaFile) -> Bool {
            let pa = pixels[a.id] ?? 0, pb = pixels[b.id] ?? 0
            if pa != pb { return pa > pb }
            if a.size != b.size { return a.size > b.size }
            let da = dates[a.id] ?? a.modified, db = dates[b.id] ?? b.modified
            if da != db { return da < db }
            if a.relativePath.count != b.relativePath.count { return a.relativePath.count < b.relativePath.count }
            return a.relativePath != b.relativePath ? a.relativePath < b.relativePath : a.id < b.id
        }
        func group(_ kind: DuplicateGroup.Kind, _ files: [MediaFile]) -> DuplicateGroup {
            let sorted = files.sorted(by: isBetter)
            return DuplicateGroup(kind: kind, ids: sorted.map(\.id), keepIDs: [sorted[0].id])
        }

        // Exact copies.
        var buckets: [String: [MediaFile]] = [:]
        for file in images {
            guard let hash = hashes[file.id] else { continue }
            buckets["\(file.size)|\(hash)", default: []].append(file)
        }
        let exact = buckets.values.filter { $0.count > 1 }.map { group(.exact, $0) }
        let inExact = Set(exact.flatMap(\.ids))
        let keepOfExact = Set(exact.compactMap(\.ids.first))

        // Similar photos: every photo outside the exact groups, and the Keep photo of each exact group.
        let candidates = images.filter { vectors[$0.id] != nil && (!inExact.contains($0.id) || keepOfExact.contains($0.id)) }
        let unit = candidates.map { VectorMath.normalize(vectors[$0.id]!) }
        var similar: [DuplicateGroup] = []
        var pending = Self.similarComponents(unit, similarity: similarity)
        while let members = pending.popLast() {
            // The Keep photo of the component, and the members similar to it.
            let keep = members.min { isBetter(candidates[$0], candidates[$1]) }!
            let close = members.filter { $0 == keep || VectorMath.dot(unit[$0], unit[keep]) >= similarity }
            if close.count > 1 {
                var g = group(.similar, close.map { candidates[$0] })
                g.keepIDs.formUnion(g.ids.filter(keepOfExact.contains))
                similar.append(g)
            }
            let isClose = Set(close)
            let rest = members.filter { !isClose.contains($0) }
            guard rest.count > 1 else { continue }
            // The other members make new groups with the same rule.
            let restComponents = Self.similarComponents(rest.map { unit[$0] }, similarity: similarity)
            pending += restComponents.map { $0.map { rest[$0] } }
        }

        func ordered(_ g: [DuplicateGroup]) -> [DuplicateGroup] {
            g.filter { !dismissed.contains($0.id) }.sorted { $0.id < $1.id }
        }
        return ordered(exact) + ordered(similar)
    }

    /// The connected components (index lists, of 2 or more) of the graph where 2 unit vectors are joined
    /// when their cosine is at least `similarity`. 1 matrix multiply per block of `blockSize` rows.
    static func similarComponents(_ unit: [Vector], similarity: Float) -> [[Int]] {
        let n = unit.count
        var parent = Array(0..<n)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        for start in stride(from: 0, to: n, by: blockSize) {
            let end = min(start + blockSize, n)
            // Each block against itself and the rows after it: every pair once.
            let cosines = VectorMath.matmul(Array(unit[start..<end]), Array(unit[start..<n]))
            for i in start..<end {
                let row = cosines[i - start]
                for j in (i + 1)..<n where row[j - start] >= similarity {
                    let a = root(i), b = root(j)
                    if a != b { parent[max(a, b)] = min(a, b) }
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for i in 0..<n { members[root(i), default: []].append(i) }
        return members.values.filter { $0.count > 1 }.sorted { $0[0] < $1[0] }
    }
}
