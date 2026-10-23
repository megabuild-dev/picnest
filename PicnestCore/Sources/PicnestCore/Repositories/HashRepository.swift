import CryptoKit
import Foundation

/// SHA-256 hashes of file contents for exact-copy detection (spec 4.9). Hashes only files whose size is
/// shared with another given file, and keeps them in `hashes.json` with the key `MediaFile.cacheKey`.
///
/// The cache trusts the key: a file whose bytes change but keeps its size and modification time gets
/// its old hash. So a cached hash only finds groups. Before clean-up trashes an exact copy, the caller
/// checks it with `freshHashes`, which never uses the cache.
public actor HashRepository {
    private static let chunkSize = 1024 * 1024
    /// The count of new hashes after which the cache is written, so a cancelled run keeps its work.
    private static let storeEvery = 64

    private let cacheURL: URL
    private var cache: [String: String]
    /// Hashes 1 file. Tests can wrap it, for example to hold a hash while the session changes.
    private let hashFile: @Sendable (URL) -> String?

    public init(cacheDirectory: URL) {
        self.init(cacheDirectory: cacheDirectory, hashFile: Self.sha256(of:))
    }

    init(cacheDirectory: URL, hashFile: @escaping @Sendable (URL) -> String?) {
        self.hashFile = hashFile
        cacheURL = cacheDirectory.appending(path: "hashes.json")
        if let data = try? Data(contentsOf: cacheURL),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = loaded
        } else {
            cache = [:]
        }
    }

    /// The hex SHA-256 of each file of `media` whose size is not unique in `media`. A file that cannot be
    /// read has no hash. `progress` gets (done, total) for the files that need a hash. Throws only when
    /// the task is cancelled.
    public func hashes(
        for media: [MediaFile], source: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MediaID: String] {
        var countBySize: [Int64: Int] = [:]
        for file in media { countBySize[file.size, default: 0] += 1 }
        let shared = media.filter { countBySize[$0.size, default: 0] > 1 }

        var result: [MediaID: String] = [:]
        var fresh: [String: String] = [:]
        progress(0, shared.count)
        for (index, file) in shared.enumerated() {
            try Task.checkCancellation()
            let key = file.cacheKey
            if let hit = cache[key] {
                result[file.id] = hit
            } else if let hash = hashFile(Self.url(of: file, in: source)) {
                result[file.id] = hash
                fresh[key] = hash
                if fresh.count >= Self.storeEvery {
                    store(fresh)
                    fresh = [:]
                }
            }
            progress(index + 1, shared.count)
        }
        store(fresh)
        return result
    }

    /// The hex SHA-256 of each file of `media`, read now: no cache is read or written. A file that cannot
    /// be read has no hash. Returns what it has when the task is cancelled.
    public func freshHashes(for media: [MediaFile], source: URL) -> [MediaID: String] {
        var result: [MediaID: String] = [:]
        for file in media {
            if Task.isCancelled { break }
            result[file.id] = hashFile(Self.url(of: file, in: source))
        }
        return result
    }

    private static func url(of file: MediaFile, in source: URL) -> URL {
        source.appending(path: file.relativePath, directoryHint: .notDirectory)
    }

    /// Reads the file in chunks of 1 MB, so a large file never sits in memory at once.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Writes the cache atomically. A failed write keeps the old file: the cache is an optimization.
    private func store(_ fresh: [String: String]) {
        guard !fresh.isEmpty else { return }
        var updated = cache
        updated.merge(fresh) { _, new in new }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: cacheURL, options: .atomic)
        } catch {
            // Keep going without the cache.
        }
        cache = updated
    }
}
