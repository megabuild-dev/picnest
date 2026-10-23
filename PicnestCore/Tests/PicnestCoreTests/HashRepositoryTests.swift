import CryptoKit
import Foundation
import Testing
@testable import PicnestCore

struct HashRepositoryTests {
    /// Writes `bytes` to `source/name` and returns its media file (size and modification time from disk).
    private func file(_ name: String, _ bytes: Data, in source: URL) throws -> MediaFile {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let url = source.appending(path: name)
        try bytes.write(to: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return MediaFile(
            id: name, relativePath: name, kind: .image, size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? Date())
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func hashesOnlySharedSizes() async throws {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        let same = Data(repeating: 7, count: 3 * 1024 * 1024 + 5)  // More than 1 chunk.
        let other = Data(repeating: 8, count: 3 * 1024 * 1024 + 5)  // Same size, other bytes.
        let unique = Data(repeating: 9, count: 100)
        let media = [
            try file("a.jpg", same, in: source), try file("b.jpg", same, in: source),
            try file("c.jpg", other, in: source), try file("d.jpg", unique, in: source),
        ]
        let repo = HashRepository(cacheDirectory: dir.url.appending(path: "Cache", directoryHint: .isDirectory))
        let reports = Reports()
        let hashes = try await repo.hashes(for: media, source: source) { done, total in reports.add(done, total) }
        #expect(hashes.keys.sorted() == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(hashes["a.jpg"] == sha256(same))
        #expect(hashes["b.jpg"] == sha256(same))
        #expect(hashes["c.jpg"] == sha256(other))
        #expect(reports.last.map { $0 == (3, 3) } == true)
    }

    @Test func hashCacheReused() async throws {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        let cache = dir.url.appending(path: "Cache", directoryHint: .isDirectory)
        let bytes = Data(repeating: 1, count: 2048)
        let a = try file("a.jpg", bytes, in: source)
        let b = try file("b.jpg", bytes, in: source)
        let first = try await HashRepository(cacheDirectory: cache).hashes(for: [a, b], source: source)
        #expect(FileManager.default.fileExists(atPath: cache.appending(path: "hashes.json").path))

        // New bytes of the same size with the old modification time: the cache key does not change,
        // so a new repository returns the cached hash and does not read the file.
        let url = source.appending(path: "a.jpg")
        try Data(repeating: 2, count: 2048).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: a.modified], ofItemAtPath: url.path)
        let second = try await HashRepository(cacheDirectory: cache).hashes(for: [a, b], source: source)
        #expect(second == first)

        // A new modification time is a new key: the file is hashed again.
        var changed = a
        changed.modified = a.modified.addingTimeInterval(10)
        let third = try await HashRepository(cacheDirectory: cache).hashes(for: [changed, b], source: source)
        #expect(third["a.jpg"] == sha256(Data(repeating: 2, count: 2048)))
    }

    @Test func unreadableFileHasNoHash() async throws {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        let a = try file("a.jpg", Data(repeating: 1, count: 10), in: source)
        let gone = MediaFile(id: "gone.jpg", relativePath: "gone.jpg", kind: .image, size: 10, modified: a.modified)
        let hashes = try await HashRepository(cacheDirectory: dir.url).hashes(for: [a, gone], source: source)
        #expect(hashes.keys.sorted() == ["a.jpg"])
    }
}
