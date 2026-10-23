import Foundation

public protocol Embedder: Sendable {
    var dimension: Int { get }
    func embedImages(_ urls: [URL]) async throws -> [Vector]
    func embedTexts(_ texts: [String]) async throws -> [Vector]
}

public enum EmbedderError: Error, Equatable { case unreadable(URL) }

extension Embedder {
    /// Embeds `urls` and gives a result per URL. It tries the whole list in one call first.
    /// If that call fails, it embeds each URL alone so that only unreadable images fail.
    public func embedImagesPartial(_ urls: [URL]) async -> [URL: Result<Vector, Error>] {
        if let vectors = try? await embedImages(urls), vectors.count == urls.count {
            return Dictionary(zip(urls, vectors.map { .success($0) }), uniquingKeysWith: { first, _ in first })
        }
        var results: [URL: Result<Vector, Error>] = [:]
        for url in urls where results[url] == nil {
            do {
                guard let vector = try await embedImages([url]).first else { throw EmbedderError.unreadable(url) }
                results[url] = .success(vector)
            } catch {
                results[url] = .failure(error)
            }
        }
        return results
    }
}
