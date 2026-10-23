import Foundation

/// Calculates image embeddings and keeps them on disk. The cache key is `MediaFile.cacheKey`.
public actor EmbeddingRepository {
    private struct Index: Codable {
        var dimension: Int
        var rows: [String: Int]
    }

    private static let batchSize = 64

    private let embedder: any Embedder
    private let indexURL: URL
    private let dataURL: URL
    private var index: Index
    private var rowCount: Int
    private var textCache: [String: Vector] = [:]

    public init(embedder: any Embedder, cacheDirectory: URL) {
        self.embedder = embedder
        indexURL = cacheDirectory.appending(path: "embeddings.index.json")
        dataURL = cacheDirectory.appending(path: "embeddings.f32")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let rowBytes = embedder.dimension * MemoryLayout<Float>.size
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: dataURL.path))?[.size] as? NSNumber)?.intValue ?? 0
        let rows = rowBytes > 0 ? fileSize / rowBytes : 0
        if let data = try? Data(contentsOf: indexURL),
           let loaded = try? JSONDecoder().decode(Index.self, from: data),
           loaded.dimension == embedder.dimension,
           fileSize % max(rowBytes, 1) == 0,
           loaded.rows.values.allSatisfy({ $0 >= 0 && $0 < rows }) {
            index = loaded
            rowCount = rows
        } else {
            index = Index(dimension: embedder.dimension, rows: [:])
            rowCount = 0
            try? FileManager.default.removeItem(at: dataURL)
            try? FileManager.default.removeItem(at: indexURL)
        }
    }

    public func embeddings(
        for media: [MediaFile], source: URL, progress: @Sendable (Int, Int) -> Void
    ) async throws -> (vectors: [MediaID: Vector], unreadable: [MediaID]) {
        let images = media.filter { $0.kind == .image }
        var vectors: [MediaID: Vector] = [:]
        var pending: [MediaFile] = []
        for file in images {
            if let vector = readRow(index.rows[file.cacheKey]) {
                vectors[file.id] = vector
            } else {
                pending.append(file)
            }
        }
        var unreadable: [MediaID] = []
        var done = vectors.count
        progress(done, images.count)

        for start in stride(from: 0, to: pending.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(pending[start..<min(start + Self.batchSize, pending.count)])
            let urls = batch.map { source.appending(path: $0.relativePath) }
            let results = await embedder.embedImagesPartial(urls)
            var fresh: [(String, Vector)] = []
            for (file, url) in zip(batch, urls) {
                if case .success(let vector)? = results[url], vector.count == embedder.dimension {
                    vectors[file.id] = vector
                    fresh.append((file.cacheKey, vector))
                } else {
                    unreadable.append(file.id)
                }
            }
            store(fresh)
            done += batch.count
            progress(done, images.count)
        }
        return (vectors, unreadable)
    }

    public func textEmbeddings(_ texts: [String]) async throws -> [Vector] {
        let missing = Array(Set(texts.filter { textCache[$0] == nil }))
        if !missing.isEmpty {
            let computed = try await embedder.embedTexts(missing)
            for (text, vector) in zip(missing, computed) { textCache[text] = vector }
        }
        return texts.map { textCache[$0] ?? Vector(repeating: 0, count: embedder.dimension) }
    }

    /// The normalized prompt vectors of each candidate, in the order of `candidates`, from 1 text call.
    public func candidateVectors(_ candidates: [Candidate]) async throws -> [[Vector]] {
        let flat = try await textEmbeddings(candidates.flatMap(\.prompts)).map(VectorMath.normalize)
        var result: [[Vector]] = []
        var start = 0
        for candidate in candidates {
            result.append(Array(flat[start..<(start + candidate.prompts.count)]))
            start += candidate.prompts.count
        }
        return result
    }

    private func readRow(_ row: Int?) -> Vector? {
        guard let row, let handle = try? FileHandle(forReadingFrom: dataURL) else { return nil }
        defer { try? handle.close() }
        let rowBytes = index.dimension * MemoryLayout<Float>.size
        guard (try? handle.seek(toOffset: UInt64(row * rowBytes))) != nil,
              let data = try? handle.read(upToCount: rowBytes), data.count == rowBytes else { return nil }
        return data.withUnsafeBytes { raw in
            (0..<index.dimension).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    /// Appends rows to the data file, then writes the index atomically. A failed write keeps the old state.
    private func store(_ entries: [(String, Vector)]) {
        guard !entries.isEmpty else { return }
        var bytes = Data()
        for (_, vector) in entries {
            for value in vector {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
            }
        }
        do {
            if !FileManager.default.fileExists(atPath: dataURL.path) {
                FileManager.default.createFile(atPath: dataURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: dataURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(rowCount * index.dimension * MemoryLayout<Float>.size))
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
            var updated = index
            for (offset, entry) in entries.enumerated() { updated.rows[entry.0] = rowCount + offset }
            try JSONEncoder().encode(updated).write(to: indexURL, options: .atomic)
            index = updated
            rowCount += entries.count
        } catch {
            // The cache is an optimization. Keep going without it.
        }
    }
}
