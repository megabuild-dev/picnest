import Foundation
import PicnestCore

/// Table-driven embedder for tests. Images are keyed by file name, texts by their text.
final class FakeEmbedder: Embedder, @unchecked Sendable {
    let dimension: Int
    private let images: [String: Vector]
    private let texts: [String: Vector]
    private let lock = NSLock()
    private var _imageURLs: [URL] = []
    private var _imageCalls = 0
    private var _textCalls = 0

    init(dimension: Int, images: [String: Vector] = [:], texts: [String: Vector] = [:]) {
        self.dimension = dimension
        self.images = images
        self.texts = texts
    }

    var imageCallCount: Int { lock.withLock { _imageCalls } }
    var textCallCount: Int { lock.withLock { _textCalls } }
    var imageURLs: [URL] { lock.withLock { _imageURLs } }

    func embedImages(_ urls: [URL]) async throws -> [Vector] {
        lock.withLock {
            _imageCalls += 1
            _imageURLs += urls
        }
        return try urls.map { url in
            guard let v = images[url.lastPathComponent] else { throw EmbedderError.unreadable(url) }
            return v
        }
    }

    func embedTexts(_ strings: [String]) async throws -> [Vector] {
        lock.withLock { _textCalls += 1 }
        return strings.map { texts[$0] ?? Vector(repeating: 0, count: dimension) }
    }
}
