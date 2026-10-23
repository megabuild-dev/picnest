import Foundation
import PicnestCore
import Synchronization
import Testing
@testable import Picnest

/// Counts `embedImages` calls. The call with number `gatedCall` waits until its task is cancelled.
final class CountingEmbedder: Embedder {
    let dimension = 4
    private let calls = Mutex(0)
    private let images = Mutex(0)
    private let gatedCall: Int?

    init(gatedCall: Int? = nil) { self.gatedCall = gatedCall }

    var callCount: Int { calls.withLock { $0 } }
    /// Total number of images passed to `embedImages`.
    var imageCount: Int { images.withLock { $0 } }

    func embedImages(_ urls: [URL]) async throws -> [Vector] {
        let number = calls.withLock { $0 += 1; return $0 }
        images.withLock { $0 += urls.count }
        if number == gatedCall {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        }
        return urls.map { _ in [1, 0, 0, 0] }
    }

    func embedTexts(_ texts: [String]) async throws -> [Vector] { texts.map { _ in [1, 0, 0, 0] } }
}

@MainActor
struct ScanViewModelTests {
    private let temp: TempDir
    private let suite = TestDefaults()

    init() throws { temp = try TempDir() }

    private func makeEnvironment(_ embedder: any Embedder) -> AppEnvironment {
        AppEnvironment(embedder: embedder, sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
    }

    private func photos(_ count: Int, in name: String = "Photos") throws -> URL {
        let folder = try temp.folder(name)
        for i in 0..<count {
            try Data([0]).write(to: folder.appending(path: String(format: "p%03d.jpg", i)))
        }
        return folder
    }

    private func model(
        _ environment: AppEnvironment, _ app: AppModel, _ folder: URL,
        openURL: @escaping (URL) -> Void = { _ in }
    ) -> ScanViewModel {
        ScanViewModel(app: app, scanService: environment.scanService, source: folder, openURL: openURL)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// Waits until the embedder gets no new images for 2 reads in a row, at most 2 s.
    private func waitUntilIdle(_ embedder: CountingEmbedder) async {
        var last = -1
        for _ in 0..<100 {
            let now = embedder.imageCount
            if now == last { return }
            last = now
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func isWelcome(_ app: AppModel) -> Bool {
        if case .welcome = app.screen { return true }
        return false
    }

    @Test func phasesChangeInOrderThenFinishOpensReview() async throws {
        let environment = makeEnvironment(FakeEmbedder())
        let app = AppModel(environment: environment)
        let folder = try photos(10)
        app.open(folder)
        let scan = model(environment, app, folder)
        scan.start()
        await scan.settled()
        await app.settled()
        #expect(scan.history.first == .preparingModel)
        #expect(scan.history.contains(.embedding(done: 10, total: 10)))
        if case .review = app.screen {} else { Issue.record("Expected the review screen, got \(app.screen)") }
    }

    @Test func cancelReturnsToWelcomeAndSecondScanUsesCache() async throws {
        let embedder = CountingEmbedder(gatedCall: 2)
        let environment = makeEnvironment(embedder)
        let app = AppModel(environment: environment)
        let folder = try photos(130)  // 3 batches of 64, 64, 2.
        app.open(folder)
        let first = model(environment, app, folder)
        first.start()
        await waitUntil { embedder.callCount >= 2 }
        first.cancel()
        await first.settled()
        #expect(isWelcome(app))
        await waitUntilIdle(embedder)
        let firstRun = embedder.imageCount

        app.open(folder)
        let second = model(environment, app, folder)
        second.start()
        await second.settled()
        await app.settled()
        let secondRun = embedder.imageCount - firstRun
        #expect(secondRun < 130)  // The cache holds the photos of the first run.
        #expect(firstRun + secondRun >= 130)
    }

    @Test func stopDoesNotNavigate() async throws {
        let embedder = CountingEmbedder(gatedCall: 1)
        let environment = makeEnvironment(embedder)
        let app = AppModel(environment: environment)
        let folder = try photos(3)
        app.open(folder)
        let scan = model(environment, app, folder)
        scan.start()
        await waitUntil { embedder.callCount >= 1 }
        scan.stop()
        await scan.settled()
        if case .scanning = app.screen {} else { Issue.record("Expected scanning, got \(app.screen)") }
    }

    /// Phase 12: no list menu. A first scan names categories from All topics.
    @Test func firstScanUsesAllTopics() async throws {
        let environment = makeEnvironment(FakeEmbedder())
        let app = AppModel(environment: environment)
        let folder = try photos(10)
        app.open(folder)
        let scan = model(environment, app, folder)
        scan.start()
        await scan.settled()
        await app.settled()
        guard case .review(let review, _) = app.screen else { Issue.record("Expected review"); return }
        #expect(review.session.candidateList == .all)
    }

    @Test func noPhotosShowsEmptyState() async throws {
        let environment = makeEnvironment(FakeEmbedder())
        let app = AppModel(environment: environment)
        let folder = try temp.folder("Empty")
        app.open(folder)
        let scan = model(environment, app, folder)
        scan.start()
        await scan.settled()
        #expect(scan.phase == .empty)
        scan.chooseAnotherFolder()
        #expect(isWelcome(app))
    }

    @Test func unreadableFolderShowsPermissionStateAndOpensSettings() async throws {
        let environment = makeEnvironment(FakeEmbedder())
        let app = AppModel(environment: environment)
        let folder = try temp.folder("Locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let opened = Mutex<[URL]>([])
        let scan = model(environment, app, folder) { url in opened.withLock { $0.append(url) } }
        scan.start()
        await scan.settled()
        #expect(scan.phase == .permissionDenied)
        #expect(scan.message == "Picnest cannot open this folder.")
        scan.openSystemSettings()
        #expect(opened.withLock { $0 }.map(\.absoluteString)
            == ["x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"])
    }

    @Test func otherErrorsFailWithReadableMessage() async throws {
        let environment = makeEnvironment(FakeEmbedder())
        let app = AppModel(environment: environment)
        let missing = temp.url.appending(path: "DoesNotExist", directoryHint: .isDirectory)
        let scan = model(environment, app, missing)
        scan.start()
        await scan.settled()
        guard case .failed(let text) = scan.phase else { Issue.record("Expected failed, got \(scan.phase)"); return }
        #expect(!text.isEmpty)
        scan.back()
        #expect(isWelcome(app))
    }

    @Test func rescanModeKeepsReviewWorkAndAddsNewPhotos() async throws {
        let environment = makeEnvironment(FakeEmbedder())
        let app = AppModel(environment: environment)
        let folder = try photos(3)
        let food = Category(id: UUID(), displayName: "Food", emoji: "🍜", prompts: ["food"], exampleIDs: [], order: 0)
        let media = (0..<3).map {
            MediaFile(id: String(format: "p%03d.jpg", $0), relativePath: String(format: "p%03d.jpg", $0), kind: .image,
                      size: 1, modified: Date(timeIntervalSince1970: 0))
        }
        try environment.sessions.save(Session(
            sourcePath: folder.path(percentEncoded: false), candidateList: .everyday, categories: [food],
            states: Dictionary(uniqueKeysWithValues: media.map { ($0.id, PhotoState.manual(food.id)) }),
            scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil))
        app.open(folder)
        await app.settled()
        try Data([0]).write(to: folder.appending(path: "p003.jpg"))  // A new photo since the last scan.

        app.rescan()
        await app.settled()
        guard case .scanning(let url, let old?) = app.screen else { Issue.record("Expected rescan, got \(app.screen)"); return }
        let scan = ScanViewModel(
            app: app, scanService: environment.scanService, source: url, rescanOf: old, openURL: { _ in })
        scan.start()
        await scan.settled()
        await app.settled()
        guard case .review(let review, _) = app.screen else { Issue.record("Expected review, got \(app.screen)"); return }
        #expect(review.session.categories.map(\.id) == [food.id])  // A first scan would make new categories.
        #expect(review.session.scan.media.count == 4)
        #expect(review.session.states["p000.jpg"] == .manual(food.id))
    }

    @Test func countTextUsesGroupingSeparator() {
        let en = Locale(identifier: "en_US")
        #expect(ScanViewModel.countText(done: 1240, total: 2413, locale: en) == "1,240 / 2,413")
    }

    @Test func etaIsNilUntilTwoEventsThenUsesRollingMean() {
        var estimator = ETAEstimator()
        let start = Date(timeIntervalSince1970: 0)
        estimator.add(done: 0, total: 1000, at: start)
        #expect(estimator.text == nil)
        estimator.add(done: 100, total: 1000, at: start.addingTimeInterval(10))  // 0.1 s per photo
        #expect(estimator.text == "About 2 minutes left")  // 900 photos left * 0.1 s = 90 s.
        estimator.add(done: 200, total: 1000, at: start.addingTimeInterval(11))
        // Only the last 64 photos count: 100 photos in 1 s, so 800 photos left take 8 s.
        #expect(estimator.text == "Less than a minute left")
    }

    // MARK: - 1 scan per folder (final review I1)

    @Test func appModelAllowsOneScanPerFolder() throws {
        let app = AppModel(environment: makeEnvironment(FakeEmbedder()))
        let a = try temp.folder("A"), b = try temp.folder("B")
        let first = try #require(app.beginScan(a))
        #expect(app.beginScan(a) == nil)
        #expect(app.beginScan(b) != nil)
        app.endScan(first)
        #expect(app.beginScan(a) != nil)
    }

    @Test func secondScanViewModelOfTheSameFolderDoesNotScan() async throws {
        let embedder = CountingEmbedder(gatedCall: 1)
        let environment = makeEnvironment(embedder)
        let app = AppModel(environment: environment)
        let folder = try photos(3)
        let first = model(environment, app, folder)
        let second = model(environment, app, folder)
        first.start()
        await waitUntil { embedder.callCount == 1 }
        second.start()
        await waitUntilIdle(embedder)
        #expect(embedder.callCount == 1)
        #expect(second.history == [.preparingModel])
        first.stop()
        await first.settled()
        // After the first scan stops, a new scan of the folder can start.
        #expect(app.beginScan(folder) != nil)
    }

}
