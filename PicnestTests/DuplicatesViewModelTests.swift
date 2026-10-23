import Foundation
import PicnestCore
import Testing
@testable import Picnest

/// The Duplicates view (spec 3.6). Real JPEG files for the hash and pixel-size reads; the Trash is the
/// in-memory `FakeTrashFileOps`, never the real Trash.
@MainActor
struct DuplicatesViewModelTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let classify = ClassifyService(settings: .default)
    private let other = PicnestCore.Category(
        id: UUID(), displayName: "Other", emoji: "📁", prompts: ["other"], exampleIDs: [], order: 0)

    init() throws { temp = try TempDir() }

    @MainActor private struct Fixture {
        let model: ReviewViewModel
        let review: ReviewService
        let ops: FakeTrashFileOps
        var duplicates: DuplicatesViewModel { model.duplicates }
    }

    /// p1, p2: exact copies (64 px). r (48 px), q (32 px): similar, r is the Keep photo.
    /// `exactNearR`: p1 and p2 look like r, so the similar group is [p1, r, q] with the exact Keep p1 in it.
    /// `noDuplicates`: only p1 and q, which are not duplicates.
    private func fixture(
        exactNearR: Bool = false, noDuplicates: Bool = false, failingNames: Set<String> = [], folder: String = "Photos"
    ) throws -> Fixture {
        let source = try temp.folder(folder)
        try writeTestJPEG(to: source.appending(path: "p1.jpg"), red: 0.8, green: 0.1, blue: 0.1, size: 64)
        try FileManager.default.copyItem(at: source.appending(path: "p1.jpg"), to: source.appending(path: "p2.jpg"))
        try writeTestJPEG(to: source.appending(path: "q.jpg"), red: 0.1, green: 0.1, blue: 0.8, size: 32)
        try writeTestJPEG(to: source.appending(path: "r.jpg"), red: 0.1, green: 0.8, blue: 0.1, size: 48)
        let names = noDuplicates ? ["p1.jpg", "q.jpg"] : ["p1.jpg", "p2.jpg", "q.jpg", "r.jpg"]
        let ops = FakeTrashFileOps(failingNames: failingNames)
        let media = try names.map { name in
            let url = source.appending(path: name)
            ops.add(url)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return MediaFile(id: name, relativePath: name, kind: .image, size: Int64(values.fileSize ?? 0),
                             modified: try #require(values.contentModificationDate))
        }
        let q: Vector = [0, 1, 0, 0], r: Vector = [0, 0.97, 0.2431, 0]
        let p: Vector = exactNearR ? r : [1, 0, 0, 0]
        let images: [MediaID: Vector] = ["p1.jpg": p, "p2.jpg": p, "q.jpg": q, "r.jpg": r]
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [other],
            states: Dictionary(uniqueKeysWithValues: names.map { ($0, PhotoState.dontMove) }),
            scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil)
        let sessions = SessionRepository(root: temp.url.appending(path: "Sessions"))
        let review = ReviewService(
            session: session, source: source, images: images, prompts: [:], classify: classify, sessions: sessions,
            embeddings: EmbeddingRepository(embedder: FakeEmbedder(), cacheDirectory: temp.url.appending(path: "Cache")),
            trash: TrashService(fileOps: ops))
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
        let model = ReviewViewModel(
            review: review, classify: classify, thumbnails: ThumbnailService(images: ImageRepository()),
            library: environment.library, app: AppModel(environment: environment), onRescan: {})
        return Fixture(model: model, review: review, ops: ops)
    }

    private func group(_ d: DuplicatesViewModel, _ kind: DuplicateGroup.Kind) throws -> DuplicateGroup {
        try #require(d.allGroups.first { $0.kind == kind })
    }

    // MARK: - Brief tests

    @Test func findsOnFirstOpenOnly() async throws {
        let f = try fixture()
        let d = f.duplicates
        #expect(d.state == .idle)
        #expect(f.model.count(of: .duplicates) == 0)  // 0 until found.
        await d.find()
        #expect(d.state == .ready)
        #expect(d.findCount == 1)
        await d.find()  // A second open reuses the result.
        #expect(d.findCount == 1)
        #expect(f.model.count(of: .duplicates) == 2)  // p2 and q.

        // A rescan makes a new review, so the next open finds again.
        let rescanned = try fixture(folder: "Photos2")
        #expect(rescanned.duplicates.state == .idle)
        await rescanned.duplicates.find()
        #expect(rescanned.duplicates.findCount == 1)
        #expect(rescanned.duplicates.exactCount == 1)
    }

    @Test func toggleKeepNeverLeavesZeroKeep() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        var similar = try group(d, .similar)
        #expect(similar.keepIDs == ["r.jpg"])
        d.toggleKeep("r.jpg", in: similar)  // The last Keep: no change.
        #expect(try group(d, .similar).keepIDs == ["r.jpg"])
        d.toggleKeep("q.jpg", in: similar)  // Similar groups can keep more than 1.
        similar = try group(d, .similar)
        #expect(similar.keepIDs == ["r.jpg", "q.jpg"])
        #expect(d.trashCount(of: similar) == 0)
        d.toggleKeep("r.jpg", in: similar)
        similar = try group(d, .similar)
        #expect(similar.keepIDs == ["q.jpg"])
        #expect(d.isKeep("q.jpg", in: similar) && !d.isKeep("r.jpg", in: similar))

        // An exact group has 1 Keep photo: a click moves it.
        let exact = try group(d, .exact)
        let keep = try #require(exact.keepIDs.first)
        let copy = try #require(exact.ids.first { $0 != keep })
        d.toggleKeep(keep, in: exact)
        #expect(try group(d, .exact).keepIDs == [keep])
        d.toggleKeep(copy, in: exact)
        #expect(try group(d, .exact).keepIDs == [copy])
    }

    @Test func trashGroupUsesKeep() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        var similar = try group(d, .similar)
        d.toggleKeep("q.jpg", in: similar)
        similar = try group(d, .similar)
        d.toggleKeep("r.jpg", in: similar)
        similar = try group(d, .similar)
        #expect(d.trashCount(of: similar) == 1)
        #expect(d.trashTitle(of: similar) == "Move 1 to Trash")

        await d.trash(similar)
        await f.review.settled()
        #expect(f.review.session.trashedIDs == ["r.jpg"])
        #expect(d.similarCount == 0)  // A group of 1 photo disappears.
        #expect(f.model.count(of: .duplicates) == 1)
        #expect(f.model.trashMessage == nil)

        f.model.undo()  // ⌘Z, as for Move to Trash.
        await f.model.settled()
        #expect(f.review.session.trashedIDs.isEmpty)
        #expect(d.similarCount == 1)
        #expect(try group(d, .similar).keepIDs == ["q.jpg"])  // The Keep choice stays.
    }

    @Test func notDuplicatesHidesGroup() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        let exact = try group(d, .exact)
        d.notDuplicates(exact)
        #expect(d.exactCount == 0)
        #expect(d.groups.isEmpty)  // The Exact copies segment shows by default.
        #expect(f.review.session.notDuplicateKeys == [exact.id])
        #expect(f.model.count(of: .duplicates) == 1)  // q only.
        #expect(f.review.session.trashed.isEmpty)
    }

    @Test func cleanUpConfirmationText() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        #expect(d.cleanUpCount == 2)
        #expect(d.cleanUpTitle == "Clean Up All (2)")
        #expect(d.cleanUpConfirmation
            == "Move 2 photos to the Trash? You can put them back with Undo or from the Trash in Finder.")

        await d.cleanUpAll()
        await f.review.settled()
        #expect(f.review.session.trashedIDs == ["p2.jpg", "q.jpg"])
        #expect(d.state == .empty)
        #expect(d.cleanUpCount == 0)
        #expect(f.model.count(of: .duplicates) == 0)

        f.model.undo()  // The clean-up is 1 undo step.
        await f.model.settled()
        #expect(f.review.session.trashedIDs.isEmpty)
        #expect(d.state == .ready)
        #expect(d.cleanUpCount == 2)
    }

    @Test func emptyStateText() async throws {
        let f = try fixture(noDuplicates: true)
        let d = f.duplicates
        await d.find()
        #expect(d.state == .empty)
        #expect(DuplicatesViewModel.emptyText == "No duplicates found.")
        #expect(DuplicatesViewModel.notice
            == "Check each group. The app moves the photos that are not marked Keep to the Trash.")
    }

    @Test func segmentsCountGroups() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        #expect(d.kind == .exact)
        #expect(d.exactCount == 1)
        #expect(d.similarCount == 1)
        #expect(d.groups.map(\.kind) == [.exact])
        d.kind = .similar
        #expect(d.groups.map(\.kind) == [.similar])
    }

    // MARK: - Controller notes

    /// Note 2 and 4: the exact Keep photo in a similar group shows as Keep and cannot be unmarked. The
    /// counts never use `ids.count - 1`.
    @Test func exactKeepInSimilarGroupShowsAsKeep() async throws {
        let f = try fixture(exactNearR: true)
        let d = f.duplicates
        await d.find()
        var similar = try group(d, .similar)
        #expect(Set(similar.ids) == ["p1.jpg", "r.jpg", "q.jpg"])
        d.toggleKeep("r.jpg", in: similar)
        similar = try group(d, .similar)
        #expect(d.isKeep("p1.jpg", in: similar) && d.isKeep("r.jpg", in: similar))
        d.toggleKeep("p1.jpg", in: similar)  // Protected: no change.
        similar = try group(d, .similar)
        #expect(d.isKeep("p1.jpg", in: similar))
        #expect(d.trashCount(of: similar) == 1)  // q only, not ids.count - 1 = 2.
        #expect(d.cleanUpCount == 2)  // p2 + q.
        #expect(f.model.count(of: .duplicates) == 2)

        await d.cleanUpAll()
        await f.review.settled()
        #expect(f.review.session.trashedIDs == ["p2.jpg", "q.jpg"])
    }

    /// Fix round 1: moving the exact Keep from p1 to p2 unlocks p1 in the similar card. The badges, the
    /// counts, and the clean-up agree. Moving it back locks p1 again.
    @Test func togglingTheExactKeepUpdatesTheSimilarCard() async throws {
        let f = try fixture(exactNearR: true)
        let d = f.duplicates
        await d.find()
        d.toggleKeep("r.jpg", in: try group(d, .similar))
        var similar = try group(d, .similar)
        #expect(similar.keepIDs == ["p1.jpg", "r.jpg"])
        #expect(d.trashCount(of: similar) == 1)

        d.toggleKeep("p2.jpg", in: try group(d, .exact))
        similar = try group(d, .similar)
        let exact = try group(d, .exact)
        #expect(exact.keepIDs == ["p2.jpg"])
        #expect(!d.isKeep("p1.jpg", in: similar))  // Not locked any more.
        #expect(similar.keepIDs == ["r.jpg"])
        #expect(d.trashCount(of: similar) == 2)  // p1 and q.
        #expect(d.trashCount(of: exact) == 1)  // p1.
        #expect(d.cleanUpCount == 2)  // p1 and q, each 1 time.
        #expect(f.model.count(of: .duplicates) == 2)

        d.toggleKeep("p1.jpg", in: try group(d, .exact))
        similar = try group(d, .similar)
        #expect(d.isKeep("p1.jpg", in: similar))
        d.toggleKeep("p1.jpg", in: similar)  // Locked again: no change.
        #expect(try group(d, .similar).keepIDs == ["p1.jpg", "r.jpg"])
        #expect(d.cleanUpCount == 2)  // p2 and q.
    }

    /// Fix round 1, test 1: the exact Keep moved from p1 to p2, then Clean Up All. p1 is trashed only when
    /// no shown card marks it Keep. The view state and the trash result agree.
    @Test func cleanUpAllAfterMovingTheExactKeep() async throws {
        for markInSimilar in [false, true] {
            let f = try fixture(exactNearR: true, folder: markInSimilar ? "Marked" : "Unmarked")
            let d = f.duplicates
            await d.find()
            d.toggleKeep("r.jpg", in: try group(d, .similar))
            d.toggleKeep("p2.jpg", in: try group(d, .exact))
            if markInSimilar { d.toggleKeep("p1.jpg", in: try group(d, .similar)) }
            let similar = try group(d, .similar), exact = try group(d, .exact)
            #expect(d.isKeep("p1.jpg", in: similar) == markInSimilar)
            #expect(d.isKeep("p1.jpg", in: exact) == markInSimilar)  // 1 Keep state in both segments.
            let expected: Set<MediaID> = markInSimilar ? ["q.jpg"] : ["p1.jpg", "q.jpg"]
            #expect(d.cleanUpCount == expected.count)

            await d.cleanUpAll()
            await f.review.settled()
            #expect(f.review.session.trashedIDs == expected, "\(markInSimilar)")
        }
    }

    @Test func cleanUpConfirmationForOnePhoto() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        d.toggleKeep("q.jpg", in: try group(d, .similar))  // The similar group keeps both.
        #expect(d.cleanUpCount == 1)  // p2.
        #expect(d.cleanUpConfirmation
            == "Move 1 photo to the Trash? You can put them back with Undo or from the Trash in Finder.")
    }

    @Test func actionsAreOffWhileACleanUpRuns() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        #expect(!d.isCleaning)
        let run = Task { await d.cleanUpAll() }
        try await waitUntil { d.isCleaning }
        await d.cleanUpAll()  // Ignored: a clean-up runs.
        await run.value
        #expect(!d.isCleaning)
        await f.review.settled()
        #expect(f.review.session.trashedIDs == ["p2.jpg", "q.jpg"])
        f.model.undo()
        await f.model.settled()
        #expect(f.review.session.trashedIDs.isEmpty)
        #expect(!f.review.canUndo)  // 1 undo step: the second clean-up did nothing.
    }

    /// Note 5: trash errors show as on the Review screen.
    @Test func cleanUpErrorsShowInTheTrashAlert() async throws {
        let f = try fixture(failingNames: ["p2.jpg", "q.jpg"])
        let d = f.duplicates
        await d.find()
        await d.cleanUpAll()
        await f.review.settled()
        let message = try #require(f.model.trashMessage)
        #expect(message.hasPrefix("The photo could not be moved to the Trash: no permission"))
        #expect(message.hasSuffix("(and 1 more)"))
    }

    /// Tiles show the file name, the pixel size, and the file size; Quick Look steps through the shown tiles.
    @Test func tileShowsNamePixelAndFileSize() async throws {
        let f = try fixture()
        let d = f.duplicates
        await d.find()
        let tile = d.tile("r.jpg")
        #expect(tile.name == "r.jpg")
        #expect(tile.pixelSize == "48 × 48")
        #expect(!tile.fileSize.isEmpty)
        d.openPreview("p1.jpg")
        #expect(d.previewURL?.lastPathComponent == "p1.jpg")
        #expect(d.previewURLs.map(\.lastPathComponent).sorted() == ["p1.jpg", "p2.jpg"])
    }
}
