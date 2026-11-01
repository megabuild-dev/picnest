import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PicnestCore
import SwiftUI
@testable import Picnest

/// Embedder for app tests. Every image and text gets the same unit vector, so no model is needed.
struct FakeEmbedder: Embedder {
    let dimension = 4

    func embedImages(_ urls: [URL]) async throws -> [Vector] {
        urls.map { _ in [1, 0, 0, 0] }
    }

    func embedTexts(_ texts: [String]) async throws -> [Vector] {
        texts.map { _ in [1, 0, 0, 0] }
    }
}

/// A temporary folder that the test deletes at the end.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "PicnestTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Makes a subfolder and returns its URL.
    func folder(_ name: String) throws -> URL {
        let folder = url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// Puts a folder with a file in it in place of `session.json` of `source`, so each session save fails.
/// The journal in the same session folder still works. Returns the folder; remove it to allow saves again.
@discardableResult
func blockSessionSaves(_ sessions: SessionRepository, source: URL) throws -> URL {
    let blocker = sessions.directory(for: source).appending(path: "session.json", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: blocker)
    try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
    try Data([1]).write(to: blocker.appending(path: "keep"))
    return blocker
}

/// A `UserDefaults` suite that only this test uses. It is removed at the end.
final class TestDefaults {
    let name = "PicnestTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit { defaults.removePersistentDomain(forName: name) }
}

/// A `FileOps` for Trash tests: an in-memory set of paths. `trash` moves a path to `/FakeTrash/<name>`.
/// Nothing touches the real disk or the real Trash.
final class FakeTrashFileOps: FileOps, @unchecked Sendable {
    private let lock = NSLock()
    private var present: Set<String> = []
    private var failing: Set<String>
    /// Hold it to make `trash` wait (a slow Trash move).
    let trashGate = Gate()

    /// `failingNames`: file names for which `trash` throws.
    init(failingNames: Set<String> = []) { failing = failingNames }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    /// Makes `trash` throw for these file names from now on.
    func setFailing(_ names: Set<String>) { locked { failing = names } }

    /// Makes a path "exist", for example a file in the fake Trash.
    func forget(_ url: URL) { locked { _ = present.remove(url.path(percentEncoded: false)) } }
    func add(_ url: URL) { locked { _ = present.insert(url.path(percentEncoded: false)) } }

    func exists(_ u: URL) -> Bool { locked { present.contains(u.path(percentEncoded: false)) } }
    func makeFolder(_ u: URL) throws {}
    func copy(_ from: URL, _ to: URL) throws {}
    func size(_ u: URL) throws -> Int64 { 1 }
    func modified(_ u: URL) throws -> Date { Date() }
    func remove(_ u: URL) throws { forget(u) }
    func removeEmptyFolder(_ u: URL) throws {}
    func isEmptyFolder(_ u: URL) -> Bool { false }
    func names(in folder: URL) -> Set<String> { [] }

    func trash(_ u: URL) throws -> URL? {
        trashGate.pass()
        if failing.contains(u.lastPathComponent) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "no permission"])
        }
        let target = URL(filePath: "/FakeTrash/\(u.lastPathComponent)")
        locked {
            present.remove(u.path(percentEncoded: false))
            present.insert(target.path(percentEncoded: false))
        }
        return target
    }

    func move(_ from: URL, _ to: URL) throws {
        locked {
            present.remove(from.path(percentEncoded: false))
            present.insert(to.path(percentEncoded: false))
        }
    }
}

/// Writes a square JPEG of 1 color to `url`, for tests that read real image files (hashes, pixel sizes).
func writeTestJPEG(to url: URL, red: CGFloat, green: CGFloat, blue: CGFloat, size: Int) throws {
    enum Failure: Error { case encode }
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw Failure.encode }
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw Failure.encode }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure.encode }
}

/// Holds a blocking call until the test releases it, so a test can act while file work runs.
/// Call `pass()` from the work (off the main actor). It waits only while the gate is held.
/// (The core tests have the same helper; the 2 test targets cannot share a file.)
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private var waiting = 0
    private let semaphore = DispatchSemaphore(value: 0)

    var waitingCount: Int { lock.withLock { waiting } }

    func hold() { lock.withLock { held = true } }

    /// Lets the waiting calls go on, and stops holding the next ones.
    func release() {
        let count = lock.withLock {
            held = false
            defer { waiting = 0 }
            return waiting
        }
        for _ in 0..<count { semaphore.signal() }
    }

    func pass() {
        let wait = lock.withLock {
            if held { waiting += 1 }
            return held
        }
        if wait { semaphore.wait() }
    }

    /// Waits until a call waits in `pass()`. Fails the test after 2 s.
    func untilWaiting() async throws {
        let end = Date().addingTimeInterval(2)
        while waitingCount == 0 {
            guard Date() < end else { throw Timeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    struct Timeout: Error {}
}

/// Waits until `condition` is true. Fails the test after 2 s.
@MainActor
func waitUntil(_ condition: () -> Bool) async throws {
    struct Timeout: Error {}
    let end = Date().addingTimeInterval(2)
    while !condition() {
        guard Date() < end else { throw Timeout() }
        await Task.yield()
    }
}

/// The real `LocalFileOps`, but `remove` waits at `removeGate` while it is held. A test holds it to keep
/// a sort or an undo running.
final class GatedFileOps: FileOps, @unchecked Sendable {
    let removeGate = Gate()
    private let local = LocalFileOps()

    func exists(_ u: URL) -> Bool { local.exists(u) }
    func makeFolder(_ u: URL) throws { try local.makeFolder(u) }
    func copy(_ from: URL, _ to: URL) throws { try local.copy(from, to) }
    func size(_ u: URL) throws -> Int64 { try local.size(u) }
    func modified(_ u: URL) throws -> Date { try local.modified(u) }
    func remove(_ u: URL) throws {
        removeGate.pass()
        try local.remove(u)
    }
    func removeEmptyFolder(_ u: URL) throws { try local.removeEmptyFolder(u) }
    func isEmptyFolder(_ u: URL) -> Bool { local.isEmptyFolder(u) }
    func names(in folder: URL) -> Set<String> { local.names(in: folder) }
    func trash(_ u: URL) throws -> URL? { try local.trash(u) }
    func move(_ from: URL, _ to: URL) throws { try local.move(from, to) }
}

/// The review fixture of the view model tests: 8 files in 2 categories (see `makeSession`) and a view model on them.
@MainActor
struct ReviewFixture {
    let temp: TempDir
    let suite = TestDefaults()
    let food = PicnestCore.Category(id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 1)
    let documents = PicnestCore.Category(
        id: UUID(), displayName: "Documents", emoji: "🧾", prompts: ["documents"], exampleIDs: [], order: 0)
    let classify = ClassifyService(settings: .default)

    init() throws { temp = try TempDir() }

    var environment: AppEnvironment {
        AppEnvironment(embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"),
                       defaults: suite.defaults)
    }

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func file(_ name: String, kind: MediaKind = .image, modified: Date? = nil) -> MediaFile {
        MediaFile(id: name, relativePath: name, kind: kind, size: 10, modified: modified ?? day(2020, 1, 1))
    }

    func auto(_ c: PicnestCore.Category, _ percent: Int, uncertain: Bool = false) -> Assignment {
        Assignment(categoryID: c.id, score: 0.3, secondCategoryID: nil, secondScore: nil, percent: percent,
                   uncertain: uncertain)
    }

    /// 8 files, 1 of each kind of tile:
    /// a 91% Food, b 62% Food (uncertain), c manual Food, d held Not sure (Food 41%, or Documents 38%),
    /// e Don't move, f unreadable, g video, h 80% Documents with a modification-time date.
    func makeSession(source: URL) -> Session {
        let s1: Float = 0.30
        let held = Assignment(
            categoryID: food.id, score: s1, secondCategoryID: documents.id,
            secondScore: s1 + ClassifySettings.default.temperature * Float(log(38.0 / 41.0)), percent: 41,
            uncertain: true)
        let media = [
            file("a.jpg", modified: day(2024, 1, 1)), file("b.jpg"), file("c.jpg"), file("d.jpg"),
            file("e.jpg"), file("f.jpg"), file("g.mov", kind: .video), file("h.jpg", modified: day(2019, 3, 3)),
        ]
        let states: [MediaID: PhotoState] = [
            "a.jpg": .auto(auto(food, 91)), "b.jpg": .auto(auto(food, 62, uncertain: true)),
            "c.jpg": .manual(food.id), "d.jpg": .heldNotSure(held), "e.jpg": .dontMove, "f.jpg": .unreadable,
            "h.jpg": .auto(auto(documents, 80)),
        ]
        let dates: [MediaID: PhotoDate] = [
            "a.jpg": PhotoDate(date: day(2024, 5, 12), source: .exif),
            "b.jpg": PhotoDate(date: day(2023, 11, 2), source: .fileNameTimestamp),
            "c.jpg": PhotoDate(date: day(2022, 7, 9), source: .exif),
            "d.jpg": PhotoDate(date: day(2021, 2, 1), source: .exif),
            "h.jpg": PhotoDate(date: day(2019, 3, 3), source: .modificationTime),
        ]
        return Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [food, documents],
            states: states, scan: ScanResult(media: media, dates: dates, skipped: [:]), sortedAt: nil)
    }

    func makeModel(onRescan: @escaping () -> Void = {}) throws -> ReviewViewModel {
        try makeModelAndReview(onRescan: onRescan).model
    }

    func makeModelAndReview(
        onRescan: @escaping () -> Void = {}, trashOps: FakeTrashFileOps = FakeTrashFileOps(), openURL: @escaping @MainActor (URL) -> Void = { _ in },
        revealURLs: @escaping @MainActor ([URL]) -> Void = { _ in },
        folderExists: @escaping (URL) -> Bool = { _ in true },
        session makeCustom: ((URL) -> Session)? = nil,
        defaults: UserDefaults? = nil) throws -> (model: ReviewViewModel, review: ReviewService) {
        let source = try temp.folder("Photos")
        let review = ReviewService(
            session: makeCustom?(source) ?? makeSession(source: source), source: source, images: [:], prompts: [:], classify: classify,
            sessions: SessionRepository(root: temp.url.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")),
            trash: TrashService(fileOps: trashOps))
        let environment = self.environment
        let model = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, app: AppModel(environment: environment), onRescan: onRescan,
            openURL: openURL, revealURLs: revealURLs, folderExists: folderExists,
            defaults: defaults ?? suite.defaults)
        return (model, review)
    }
}
