import Foundation
import Testing
@testable import PicnestCore

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelRequested = false
    func set(_ t: Task<Void, Never>) {
        lock.withLock { task = t; if cancelRequested { t.cancel() } }
    }
    func cancel() {
        lock.withLock { cancelRequested = true; task?.cancel() }
    }
}

struct EmbeddingRepositoryTests {
    private func makeMedia(_ names: [String], in dir: URL, size: Int = 32) throws -> [MediaFile] {
        try names.map { name in
            let url = dir.appending(path: name)
            try TestImages.writeJPEG(to: url, color: (10, 20, 30), size: size)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return MediaFile(id: name, relativePath: name, kind: .image,
                             size: (attrs[.size] as! NSNumber).int64Value,
                             modified: attrs[.modificationDate] as! Date)
        }
    }

    private func table(_ names: [String]) -> [String: Vector] {
        Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, [Float($0), 1, 2]) })
    }

    @Test func secondCallUsesCache() async throws {
        let src = try TempDir(), cache = try TempDir()
        let names = ["a.jpg", "b.jpg", "c.jpg"]
        let media = try makeMedia(names, in: src.url)
        let first = FakeEmbedder(dimension: 3, images: table(names))
        let r1 = try await EmbeddingRepository(embedder: first, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(r1.vectors.count == 3)
        let second = FakeEmbedder(dimension: 3, images: table(names))
        let r2 = try await EmbeddingRepository(embedder: second, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(second.imageCallCount == 0)
        #expect(r2.vectors == r1.vectors)
        #expect(r2.vectors["b.jpg"] == [1, 1, 2])
    }

    @Test func rekeyPointsAMovedFileAtItsCachedVector() async throws {
        let src = try TempDir(), cache = try TempDir()
        let names = ["a.jpg", "b.jpg"]
        let media = try makeMedia(names, in: src.url)
        _ = try await EmbeddingRepository(embedder: FakeEmbedder(dimension: 3, images: table(names)),
                                          cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })

        // Move a.jpg into a sub-folder and re-key the cache by hand (an in-place organize, spec 7.2).
        let folder = src.url.appending(path: "Food", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: src.url.appending(path: "a.jpg"), to: folder.appending(path: "a.jpg"))
        var moved = media[0]
        moved.id = "Food/a.jpg"
        moved.relativePath = "Food/a.jpg"
        await EmbeddingRepository(embedder: FakeEmbedder(dimension: 3, images: table(names)), cacheDirectory: cache.url)
            .rekey([media[0].cacheKey: moved.cacheKey])

        let second = FakeEmbedder(dimension: 3, images: table(names))
        let r = try await EmbeddingRepository(embedder: second, cacheDirectory: cache.url)
            .embeddings(for: [moved], source: src.url, progress: { _, _ in })
        #expect(second.imageCallCount == 0)  // The re-keyed row was found: no embedding ran.
        #expect(r.vectors["Food/a.jpg"] == [0, 1, 2])
    }

    @Test func changedFileIsEmbeddedAgain() async throws {
        let src = try TempDir(), cache = try TempDir()
        let names = ["a.jpg", "b.jpg", "c.jpg"]
        var media = try makeMedia(names, in: src.url)
        _ = try await EmbeddingRepository(embedder: FakeEmbedder(dimension: 3, images: table(names)),
                                          cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        try #require(media.count >= 2)
        media[1].size += 1
        let second = FakeEmbedder(dimension: 3, images: table(names))
        _ = try await EmbeddingRepository(embedder: second, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(second.imageCallCount == 1)
        #expect(second.imageURLs.map(\.lastPathComponent) == ["b.jpg"])
    }

    @Test func changedDimensionDiscardsCache() async throws {
        let src = try TempDir(), cache = try TempDir()
        let names = ["a.jpg"]
        let media = try makeMedia(names, in: src.url)
        _ = try await EmbeddingRepository(embedder: FakeEmbedder(dimension: 3, images: table(names)),
                                          cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        let second = FakeEmbedder(dimension: 2, images: ["a.jpg": [5, 6]])
        let r = try await EmbeddingRepository(embedder: second, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(second.imageCallCount == 1)
        #expect(r.vectors["a.jpg"] == [5, 6])
    }

    @Test func corruptCacheStartsFresh() async throws {
        let src = try TempDir(), cache = try TempDir()
        let media = try makeMedia(["a.jpg"], in: src.url)
        try Data("garbage".utf8).write(to: cache.url.appending(path: "embeddings.index.json"))
        try Data("xx".utf8).write(to: cache.url.appending(path: "embeddings.f32"))
        let fake = FakeEmbedder(dimension: 3, images: table(["a.jpg"]))
        let r = try await EmbeddingRepository(embedder: fake, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(r.vectors["a.jpg"] == [0, 1, 2])
    }

    @Test func cancelKeepsFinishedBatches() async throws {
        let src = try TempDir(), cache = try TempDir()
        let names = (0..<130).map { String(format: "p%03d.jpg", $0) }
        let media = try makeMedia(names, in: src.url)
        let box = TaskBox()
        let repo = EmbeddingRepository(embedder: FakeEmbedder(dimension: 3, images: table(names)),
                                       cacheDirectory: cache.url)
        let task = Task {
            do {
                _ = try await repo.embeddings(for: media, source: src.url, progress: { done, _ in
                    if done >= 64 { box.cancel() }
                })
                Issue.record("expected cancellation")
            } catch is CancellationError {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
        box.set(task)
        await task.value
        let second = FakeEmbedder(dimension: 3, images: table(names))
        let r = try await EmbeddingRepository(embedder: second, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(second.imageURLs.count <= 66)
        #expect(r.vectors.count == 130)
    }

    @Test func unreadableFileIsReported() async throws {
        let src = try TempDir(), cache = try TempDir()
        var media = try makeMedia(["a.jpg", "b.jpg"], in: src.url)
        try Data((0..<64).map { _ in UInt8.random(in: 0...255) }).write(to: src.url.appending(path: "bad.jpg"))
        media.append(MediaFile(id: "bad.jpg", relativePath: "bad.jpg", kind: .image, size: 64, modified: Date()))
        media.append(MediaFile(id: "v.mov", relativePath: "v.mov", kind: .video, size: 1, modified: Date()))
        let fake = FakeEmbedder(dimension: 3, images: table(["a.jpg", "b.jpg"]))
        let r = try await EmbeddingRepository(embedder: fake, cacheDirectory: cache.url)
            .embeddings(for: media, source: src.url, progress: { _, _ in })
        #expect(r.unreadable == ["bad.jpg"])
        #expect(Set(r.vectors.keys) == ["a.jpg", "b.jpg"])
    }

    @Test func textEmbeddingsAreCachedInMemory() async throws {
        let cache = try TempDir()
        let fake = FakeEmbedder(dimension: 3, texts: ["cat": [1, 0, 0], "dog": [0, 1, 0]])
        let repo = EmbeddingRepository(embedder: fake, cacheDirectory: cache.url)
        let a = try await repo.textEmbeddings(["cat", "dog"])
        let b = try await repo.textEmbeddings(["dog", "cat"])
        #expect(a == [[1, 0, 0], [0, 1, 0]])
        #expect(b == [[0, 1, 0], [1, 0, 0]])
        #expect(fake.textCallCount == 1)
    }
}
