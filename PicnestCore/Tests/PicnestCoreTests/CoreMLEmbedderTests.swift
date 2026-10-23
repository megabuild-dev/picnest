import Foundation
import Testing
@testable import PicnestCore

private let modelsAvailable = ProcessInfo.processInfo.environment["PICNEST_MODELS"] != nil

/// `<repo>/Models`, filled by `scripts/fetch-models.sh`.
private let modelsDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // PicnestCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // PicnestCore
    .deletingLastPathComponent()  // macos
    .appending(path: "Models", directoryHint: .isDirectory)

private func fixture(_ name: String) throws -> URL {
    let file = name as NSString
    return try #require(Bundle.module.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension))
}

private func dot(_ a: Vector, _ b: Vector) -> Float { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
private func norm(_ a: Vector) -> Float { dot(a, a).squareRoot() }

@Suite struct CoreMLEmbedderTests {
    @Test(.enabled(if: modelsAvailable)) func catImageMatchesCatText() async throws {
        let e = try CoreMLEmbedder(size: .s0, modelDirectory: modelsDir)
        let img = try await e.embedImages([fixture("cat.jpg")])[0]
        let txt = try await e.embedTexts(["a photo of a cat", "a screenshot of a phone"])
        #expect(abs(norm(img) - 1) < 1e-3)
        try #require(txt.count >= 2)
        #expect(dot(img, txt[0]) > dot(img, txt[1]))
    }

    @Test(.enabled(if: modelsAvailable)) func concurrentCallsMatchSequentialResults() async throws {
        let e = try CoreMLEmbedder(size: .s0, modelDirectory: modelsDir)
        let cat = try fixture("cat.jpg")
        let expectedImage = try await e.embedImages([cat])[0]
        let expectedText = try await e.embedTexts(["a photo of a cat"])[0]
        try await withThrowingTaskGroup(of: (Vector, Vector).self) { group in
            for _ in 0..<8 {
                group.addTask {
                    async let img = e.embedImages([cat])
                    async let txt = e.embedTexts(["a photo of a cat"])
                    return try await (img[0], txt[0])
                }
            }
            for try await (img, txt) in group {
                #expect(dot(img, expectedImage) > 0.999)
                #expect(dot(txt, expectedText) > 0.999)
            }
        }
    }
}
