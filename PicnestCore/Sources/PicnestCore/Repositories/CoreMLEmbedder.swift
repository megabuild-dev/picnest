import CoreML
import Foundation
import ImageIO
import Vision

/// MobileCLIP model sizes published in the Hugging Face repo `apple/coreml-mobileclip`.
public enum MobileCLIPSize: String, CaseIterable, Sendable {
    case s0, s1, s2, b

    /// File name stem in `apple/coreml-mobileclip`. The repo publishes "B" as the LT variant (`blt`).
    public var modelStem: String {
        switch self {
        case .s0: "mobileclip_s0"
        case .s1: "mobileclip_s1"
        case .s2: "mobileclip_s2"
        case .b: "mobileclip_blt"
        }
    }

    /// The size whose `modelStem` is `stem`, or nil for an unknown stem.
    public init?(modelStem stem: String) {
        guard let size = Self.allCases.first(where: { $0.modelStem == stem }) else { return nil }
        self = size
    }

    public var imagePackageName: String { "\(modelStem)_image.mlpackage" }
    public var textPackageName: String { "\(modelStem)_text.mlpackage" }
}

/// MobileCLIP image and text encoders run with Core ML.
///
/// Model I/O (all sizes): image input `image` (BGRA, 256x256 for S0/S1/S2, 224x224 for B),
/// text input `text` (Int32 `[1, 77]`), output `final_emb_1` (Float32 `[1, 512]`).
/// Input and output names are read from the model description, not hard-coded.
///
/// Concurrency: each model has its own serial `DispatchQueue`. All image decoding, tokenizing
/// and Core ML predictions run on that queue, bridged with a continuation. Concurrent callers are
/// serialized per model, and the Swift cooperative thread pool never blocks on Core ML work.
/// The class is `@unchecked Sendable` because its stored properties are immutable and every
/// `MLModel` call happens on the model's own queue.
public final class CoreMLEmbedder: Embedder, @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case missingModel(URL)
        case unexpectedModel(String)
    }

    static let batchSize = 16
    /// Cache folder name when the process has no bundle id (`swift test`, ModelBench).
    static let defaultBundleIdentifier = "dev.megabuild.picnest"

    public let dimension: Int

    // Immutable after init. Use `imageModel` only on `imageQueue`, `textModel` only on `textQueue`.
    private let imageQueue = DispatchQueue(label: "PicnestCore.CoreMLEmbedder.image", qos: .userInitiated)
    private let textQueue = DispatchQueue(label: "PicnestCore.CoreMLEmbedder.text", qos: .userInitiated)
    private let imageModel: MLModel
    private let textModel: MLModel
    private let imageInput: String
    private let imageOutput: String
    private let imageConstraint: MLImageConstraint
    private let textInput: String
    private let textOutput: String
    private let tokenizer: CLIPTokenizer

    public init(size: MobileCLIPSize, modelDirectory: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        imageModel = try MLModel(contentsOf: Self.compiledModel(modelDirectory.appending(path: size.imagePackageName)),
                                 configuration: config)
        textModel = try MLModel(contentsOf: Self.compiledModel(modelDirectory.appending(path: size.textPackageName)),
                                configuration: config)

        let imageDesc = imageModel.modelDescription
        guard let (inName, inDesc) = imageDesc.inputDescriptionsByName.first(where: { $0.value.type == .image }),
              let constraint = inDesc.imageConstraint,
              let outName = imageDesc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key
        else { throw Failure.unexpectedModel(size.imagePackageName) }

        let textDesc = textModel.modelDescription
        guard let textIn = textDesc.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key,
              let (textOut, textOutDesc) = textDesc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray }),
              let dim = textOutDesc.multiArrayConstraint?.shape.last?.intValue
        else { throw Failure.unexpectedModel(size.textPackageName) }

        imageInput = inName
        imageOutput = outName
        imageConstraint = constraint
        textInput = textIn
        textOutput = textOut
        dimension = dim
        tokenizer = try CLIPTokenizer()
    }

    // MARK: Embedder

    public func embedImages(_ urls: [URL]) async throws -> [Vector] {
        var out: [Vector] = []
        out.reserveCapacity(urls.count)
        for start in stride(from: 0, to: urls.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(urls[start..<min(start + Self.batchSize, urls.count)])
            out += try await run(on: imageQueue) { try self.embedImageBatch(batch) }
        }
        return out
    }

    public func embedTexts(_ texts: [String]) async throws -> [Vector] {
        var out: [Vector] = []
        out.reserveCapacity(texts.count)
        for start in stride(from: 0, to: texts.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(texts[start..<min(start + Self.batchSize, texts.count)])
            out += try await run(on: textQueue) { try self.embedTextBatch(batch) }
        }
        return out
    }

    // MARK: Queue work

    /// Runs blocking work on `queue` and resumes the caller with its result.
    private func run<T: Sendable>(on queue: DispatchQueue, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// Call only on `imageQueue`.
    private func embedImageBatch(_ urls: [URL]) throws -> [Vector] {
        let providers = try urls.map { url -> MLFeatureProvider in
            try MLDictionaryFeatureProvider(dictionary: [imageInput: imageFeature(url)])
        }
        return try predict(imageModel, providers, output: imageOutput)
    }

    /// Call only on `textQueue`.
    private func embedTextBatch(_ texts: [String]) throws -> [Vector] {
        let providers = try texts.map { text -> MLFeatureProvider in
            let ids = tokenizer.encode(text)
            let array = try MLMultiArray(shape: [1, NSNumber(value: ids.count)], dataType: .int32)
            array.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                for (i, id) in ids.enumerated() { ptr[i] = id }
            }
            return try MLDictionaryFeatureProvider(dictionary: [textInput: MLFeatureValue(multiArray: array)])
        }
        return try predict(textModel, providers, output: textOutput)
    }

    // MARK: Helpers

    private func predict(_ model: MLModel, _ providers: [MLFeatureProvider], output: String) throws -> [Vector] {
        let results = try model.predictions(fromBatch: MLArrayBatchProvider(array: providers))
        return try (0..<results.count).map { i in
            guard let array = results.features(at: i).featureValue(for: output)?.multiArrayValue else {
                throw Failure.unexpectedModel("missing output \(output)")
            }
            return Self.l2Normalized(MLShapedArray<Float>(converting: array).scalars)
        }
    }

    /// Decodes the image with its EXIF orientation applied, then center-crops and scales it to the model input.
    private func imageFeature(_ url: URL) throws -> MLFeatureValue {
        guard let image = Self.loadOrientedImage(url, minSide: max(imageConstraint.pixelsWide, imageConstraint.pixelsHigh))
        else { throw EmbedderError.unreadable(url) }
        do {
            return try MLFeatureValue(
                cgImage: image, constraint: imageConstraint,
                options: [.cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue]
            )
        } catch {
            throw EmbedderError.unreadable(url)
        }
    }

    /// Returns the image upright. It decodes at a reduced size whose short side is at least `minSide`.
    static func loadOrientedImage(_ url: URL, minSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0
        else { return nil }
        let long = max(w, h), short = min(w, h)
        let target = min(long, Int((Double(minSide) * Double(long) / Double(short)).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func l2Normalized(_ v: Vector) -> Vector {
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return n > 0 ? v.map { $0 / n } : v
    }

    /// Compiles an `.mlpackage` once and caches the `.mlmodelc` in `~/Library/Caches/<bundle id>/Models/`.
    /// It compiles again when the package is newer than the cached copy.
    static func compiledModel(_ package: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: package.path) else { throw Failure.missingModel(package) }
        let cacheDir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: Bundle.main.bundleIdentifier ?? defaultBundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cached = cacheDir.appending(path: package.deletingPathExtension().lastPathComponent + ".mlmodelc",
                                        directoryHint: .isDirectory)

        // One compile at a time in this process, so a second init never sees a half-written cache.
        compileLock.lock()
        defer { compileLock.unlock() }

        if isFresh(cached, for: package) { return cached }
        let compiled = try MLModel.compileModel(at: package)
        if fm.fileExists(atPath: cached.path) { try fm.removeItem(at: cached) }
        do {
            try fm.moveItem(at: compiled, to: cached)
        } catch where isFresh(cached, for: package) {
            // Another process put a fresh copy in place first. Use it.
            try? fm.removeItem(at: compiled)
        }
        return cached
    }

    private static let compileLock = NSLock()

    private static func isFresh(_ cached: URL, for package: URL) -> Bool {
        guard let cachedDate = modificationDate(cached), let sourceDate = newestModificationDate(package) else {
            return false
        }
        return cachedDate >= sourceDate
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func newestModificationDate(_ package: URL) -> Date? {
        guard let files = FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return modificationDate(package) }
        var newest = modificationDate(package)
        for case let file as URL in files {
            if let d = modificationDate(file), d > (newest ?? .distantPast) { newest = d }
        }
        return newest
    }
}
