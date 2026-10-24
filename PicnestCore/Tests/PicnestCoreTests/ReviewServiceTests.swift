import Foundation
import Testing
@testable import PicnestCore

/// Serialized: some tests use the real Trash (with unique file names; see `realFixture`).
@MainActor
@Suite(.serialized)
struct ReviewServiceTests {
    private static let settings = ClassifySettings(
        minScore: 0.22, minMargin: 0.02, temperature: 0.01, exampleScale: 1, exampleOffset: 0)
    private let classify = ClassifyService(settings: ReviewServiceTests.settings)

    private let catA = Category(id: UUID(), displayName: "A", emoji: "🅰️", prompts: ["a"], exampleIDs: [], order: 0)
    private let catB = Category(id: UUID(), displayName: "B", emoji: "🅱️", prompts: ["b"], exampleIDs: [], order: 1)
    private let catC = Category(id: UUID(), displayName: "C", emoji: "©️", prompts: ["c"], exampleIDs: [], order: 2)

    /// Prompt vectors: A = e1, B = e2, C = e4. The third axis is filler.
    private static let texts: [String: Vector] = ["a": [1, 0, 0, 0], "b": [0, 1, 0, 0], "c": [0, 0, 0, 1]]

    /// A unit vector with cosines `a`, `b`, `c` against the A, B, C prompts.
    private static func photo(_ a: Float, _ b: Float, _ c: Float = 0) -> Vector {
        [a, b, (1 - a * a - b * b - c * c).squareRoot(), c]
    }

    /// a1, a2: certain A (a1 is certain B when A is gone). b1: certain B.
    /// u1, u3: not sure, best A. u2: not sure, best B. v1: video. x1: unreadable.
    private static let images: [MediaID: Vector] = [
        "a1.jpg": photo(0.8, 0.5, 0.33),
        "a2.jpg": photo(0.9, 0.1),
        "b1.jpg": photo(0.1, 0.9),
        "u1.jpg": photo(0.30, 0.29),
        "u2.jpg": photo(0.29, 0.30),
        "u3.jpg": photo(0.20, 0.10),
    ]

    private struct Fixture {
        let service: ReviewService
        let root: TempDir
        let source: URL
        let sessions: SessionRepository
    }

    private func media(_ id: MediaID, _ kind: MediaKind = .image) -> MediaFile {
        MediaFile(id: id, relativePath: id, kind: kind, size: 10, modified: Date(timeIntervalSince1970: 1000))
    }

    /// `extra` adds 1 photo with no vector, state Don't move (for the real-Trash tests).
    private func makeSession(source: URL, extra: MediaID? = nil) -> Session {
        let ids = Self.images.keys.sorted()
        let files = (ids + ["x1.jpg"] + [extra].compactMap { $0 }).sorted().map { media($0) } + [media("v1.mov", .video)]
        let categories = [catA, catB, catC]
        var fixed: [MediaID: PhotoState] = ["x1.jpg": .unreadable]
        if let extra { fixed[extra] = .dontMove }
        let states = classify.classify(
            states: fixed, categories: categories, images: Self.images, prompts: prompts)
        return Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: categories,
            states: states, scan: ScanResult(media: files, dates: [:], skipped: [:]), sortedAt: nil)
    }

    private var prompts: [CategoryID: [Vector]] {
        [catA.id: [Self.texts["a"]!], catB.id: [Self.texts["b"]!], catC.id: [Self.texts["c"]!]]
    }

    private func fixture(
        texts: [String: Vector] = ReviewServiceTests.texts, trash: TrashService = TrashService(),
        extra: MediaID? = nil
    ) throws -> Fixture {
        let root = try TempDir()
        let source = root.url.appending(path: "Photos", directoryHint: .isDirectory)
        let sessions = SessionRepository(root: root.url.appending(path: "Sessions", directoryHint: .isDirectory))
        let embeddings = EmbeddingRepository(
            embedder: FakeEmbedder(dimension: 4, texts: texts), cacheDirectory: sessions.directory(for: source))
        let service = ReviewService(
            session: makeSession(source: source, extra: extra), source: source, images: Self.images, prompts: prompts,
            classify: classify, sessions: sessions, embeddings: embeddings, trash: trash)
        return Fixture(service: service, root: root, source: source, sessions: sessions)
    }

    private func category(_ id: CategoryID, _ s: ReviewService) -> Category? {
        s.session.categories.first { $0.id == id }
    }

    private func assignment(_ id: MediaID, _ s: ReviewService) -> Assignment? {
        switch s.session.states[id] {
        case .auto(let a)?, .heldNotSure(let a)?: a
        default: nil
        }
    }

    // MARK: - Fixture check

    @Test func fixtureHasExpectedStartStates() throws {
        let s = try fixture().service
        #expect(assignment("a1.jpg", s)?.categoryID == catA.id)
        #expect(assignment("a1.jpg", s)?.uncertain == false)
        #expect(assignment("b1.jpg", s)?.categoryID == catB.id)
        #expect(assignment("u1.jpg", s)?.uncertain == true)
        #expect(assignment("u2.jpg", s)?.categoryID == catB.id)
        #expect(assignment("u2.jpg", s)?.uncertain == true)
        #expect(assignment("u3.jpg", s)?.categoryID == catA.id)
        #expect(assignment("u3.jpg", s)?.uncertain == true)
        #expect(!s.canUndo)
        #expect(!s.canRedo)
    }

    // MARK: - Move

    @Test func moveMakesManualAndExample() async throws {
        let f = try fixture()
        let s = f.service
        s.move(["a2.jpg"], to: catA.id)
        #expect(category(catA.id, s)?.exampleIDs == ["a2.jpg"])
        s.move(["a2.jpg", "u1.jpg"], to: catB.id)
        // The direct change is visible at once.
        #expect(s.session.states["a2.jpg"] == .manual(catB.id))
        #expect(s.session.states["u1.jpg"] == .manual(catB.id))
        #expect(category(catB.id, s)?.exampleIDs == ["a2.jpg", "u1.jpg"])
        #expect(category(catA.id, s)?.exampleIDs == [])
        #expect(s.canUndo)

        await s.settled()
        #expect(s.session.states["a2.jpg"] == .manual(catB.id))
        // u3 is close to the new example u1, so it now goes to B.
        #expect(assignment("u3.jpg", s)?.categoryID == catB.id)
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    @Test func moveIgnoresUnknownIDsAndCategories() async throws {
        let s = try fixture().service
        let before = s.session
        s.move(["nope.jpg"], to: catA.id)
        s.move(["a1.jpg"], to: UUID())
        await s.settled()
        #expect(s.session == before)
        #expect(!s.canUndo)
    }

    @Test func markSortedSavesSortDate() async throws {
        let f = try fixture()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        f.service.markSorted(at: date)
        await f.service.settled()
        #expect(f.service.session.sortedAt == date)
        #expect(try f.sessions.load(source: f.source)?.sortedAt == date)
    }

    // MARK: - Organize in place

    @Test func applyOrganizeReKeysTheSession() async throws {
        let f = try fixture()
        let s = f.service
        s.move(["a2.jpg"], to: catA.id)  // a2 becomes an example of A.
        await s.settled()
        #expect(category(catA.id, s)?.exampleIDs == ["a2.jpg"])

        await s.applyOrganize([
            OrganizeMove(mediaID: "a1.jpg", to: "A/2024-05-12_A_001.jpg"),
            OrganizeMove(mediaID: "a2.jpg", to: "A/2024-05-12_A_002.jpg"),
        ])

        #expect(s.session.states["a1.jpg"] == nil)
        #expect(s.session.states["A/2024-05-12_A_001.jpg"] != nil)
        #expect(s.session.states["A/2024-05-12_A_002.jpg"] == .manual(catA.id))
        #expect(category(catA.id, s)?.exampleIDs == ["A/2024-05-12_A_002.jpg"])
        #expect(s.session.scan.media.contains {
            $0.id == "A/2024-05-12_A_001.jpg" && $0.relativePath == "A/2024-05-12_A_001.jpg"
        })
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    /// Final review I4: a failed save sets `saveError`, and `retrySave` saves again.
    @Test func failedSaveCanBeRetried() async throws {
        let f = try fixture()
        let folder = f.sessions.directory(for: f.source)
        let directory = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent, directoryHint: .notDirectory)
        // A file in place of the session folder makes each save fail.
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: directory)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        f.service.markSorted(at: date)
        #expect(f.service.saveError != nil)

        try FileManager.default.removeItem(at: directory)
        f.service.retrySave()
        #expect(f.service.saveError == nil)
        #expect(try f.sessions.load(source: f.source)?.sortedAt == date)

        try FileManager.default.removeItem(at: folder)
        try Data([1]).write(to: directory)
        f.service.retrySave()
        #expect(f.service.saveError != nil)
        f.service.dismissSaveError()
        #expect(f.service.saveError == nil)
    }

    // MARK: - Accept

    @Test func acceptBestGuessOnlyChangesNotSurePhotos() async throws {
        let s = try fixture().service
        let a1 = s.session.states["a1.jpg"]
        s.acceptBestGuess(["u1.jpg", "u2.jpg", "a1.jpg", "nope.jpg"])
        #expect(s.session.states["u1.jpg"] == .manual(catA.id))
        #expect(s.session.states["u2.jpg"] == .manual(catB.id))
        #expect(s.session.states["a1.jpg"] == a1)
        await s.settled()
        #expect(s.counts().changedByYou == 2)
    }

    @Test func acceptBestGuessMakesExample() async throws {
        let s = try fixture().service
        s.move(["a2.jpg"], to: catA.id)
        s.move(["b1.jpg"], to: catC.id)
        s.acceptBestGuess(["u2.jpg"])
        #expect(s.session.states["u2.jpg"] == .manual(catB.id))
        #expect(category(catB.id, s)?.exampleIDs == ["u2.jpg"])
        s.acceptBestGuess(["u1.jpg"])  // Best guess A: the photo is an example of A only.
        #expect(category(catA.id, s)?.exampleIDs == ["a2.jpg", "u1.jpg"])
        s.undo()
        await s.settled()
        // u3 was not sure with best guess A; the accepted u2 is very similar, so u3 now goes to B.
        guard case .auto(let a)? = s.session.states["u3.jpg"] else { Issue.record("u3 is not auto"); return }
        #expect(a.categoryID == catB.id)
        #expect(!a.uncertain)
    }

    @Test func acceptAllEmptiesNotSure() async throws {
        let s = try fixture().service
        #expect(s.counts().notSure == 3)
        s.acceptAllNotSure()
        #expect(s.counts().notSure == 0)
        #expect(s.notSureGroups.isEmpty)
        await s.settled()
        #expect(s.counts().notSure == 0)
        #expect(s.counts().changedByYou == 3)
    }

    @Test func acceptGroupAcceptsOnlyThatGroup() async throws {
        let s = try fixture().service
        s.acceptGroup(bestCategory: catA.id)
        #expect(s.session.states["u1.jpg"] == .manual(catA.id))
        #expect(s.session.states["u3.jpg"] == .manual(catA.id))
        #expect(s.session.states["u2.jpg"]?.isNotSure == true)
        await s.settled()
    }

    @Test func heldNotSureCanBeAccepted() async throws {
        let s = try fixture().service
        s.delete(catA.id)
        s.acceptBestGuess(["a1.jpg"])
        #expect(s.session.states["a1.jpg"] == .manual(catB.id))
        await s.settled()
    }

    // MARK: - Don't move

    @Test func dontMoveSetsStateAndDropsExample() async throws {
        let s = try fixture().service
        s.move(["a2.jpg"], to: catA.id)
        s.dontMove(["a2.jpg", "b1.jpg", "nope.jpg"])
        #expect(s.session.states["a2.jpg"] == .dontMove)
        #expect(s.session.states["b1.jpg"] == .dontMove)
        #expect(category(catA.id, s)?.exampleIDs == [])
        await s.settled()
        #expect(s.counts().dontMove == 2)
    }

    // MARK: - Categories

    @Test func addCategoryUsesPhotoOfPromptAndClassifiesAgain() async throws {
        var texts = Self.texts
        texts["a photo of Filler"] = [0, 0, 1, 0]
        let f = try fixture(texts: texts)
        let s = f.service
        let id = s.addCategory(name: "Filler", emoji: "🧪")
        let added = try #require(category(id, s))
        #expect(added.displayName == "Filler")
        #expect(added.emoji == "🧪")
        #expect(added.prompts == ["a photo of Filler"])
        #expect(added.order == 3)
        #expect(added.exampleIDs.isEmpty)
        await s.settled()
        // u3 is mostly on the filler axis.
        #expect(assignment("u3.jpg", s)?.categoryID == id)
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    @Test func renameSetEmojiAndReorder() async throws {
        let f = try fixture()
        let s = f.service
        s.rename(catA.id, to: "Food")
        s.setEmoji(catA.id, "🍔")
        s.rename(UUID(), to: "Ignored")
        #expect(category(catA.id, s)?.displayName == "Food")
        #expect(category(catA.id, s)?.emoji == "🍔")
        #expect(category(catA.id, s)?.prompts == ["a"])

        s.reorder([catC.id, catA.id, catB.id])
        #expect(category(catC.id, s)?.order == 0)
        #expect(category(catA.id, s)?.order == 1)
        #expect(category(catB.id, s)?.order == 2)
        #expect(s.session.categories.map(\.id) == [catC.id, catA.id, catB.id])
        await s.settled()
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    @Test func mergeKeepsManualPicks() async throws {
        let s = try fixture().service
        s.move(["a2.jpg"], to: catB.id)
        s.move(["u3.jpg"], to: catA.id)
        s.merge(catB.id, into: catA.id)
        #expect(s.session.states["a2.jpg"] == .manual(catA.id))
        #expect(s.session.states["u3.jpg"] == .manual(catA.id))
        #expect(category(catB.id, s) == nil)
        #expect(Set(category(catA.id, s)?.exampleIDs ?? []) == ["a2.jpg", "u3.jpg"])
        await s.settled()
        #expect(s.session.states["a2.jpg"] == .manual(catA.id))
        // b1 was auto in B; it is classified again against the remaining categories.
        #expect(assignment("b1.jpg", s)?.categoryID != catB.id)
        #expect(s.session.states.values.allSatisfy { state in
            if case .auto(let a) = state { return a.categoryID != catB.id }
            return true
        })
    }

    @Test func deleteHoldsPhotosInNotSureEvenIfConfident() async throws {
        let s = try fixture().service
        s.move(["u1.jpg"], to: catA.id)
        s.delete(catA.id)
        #expect(category(catA.id, s) == nil)
        guard case .heldNotSure(let a)? = s.session.states["a1.jpg"] else {
            Issue.record("a1: \(String(describing: s.session.states["a1.jpg"]))"); return
        }
        #expect(a.categoryID == catB.id)
        #expect(!a.uncertain)  // A confident photo still stays in Not sure.
        guard case .heldNotSure(let m)? = s.session.states["u1.jpg"] else {
            Issue.record("u1: \(String(describing: s.session.states["u1.jpg"]))"); return
        }
        #expect(m.categoryID != catA.id)
        #expect(s.session.states["u3.jpg"].map { if case .heldNotSure = $0 { true } else { false } } == true)
        #expect(s.session.states["b1.jpg"].map { if case .auto = $0 { true } else { false } } == true)

        await s.settled()
        #expect(s.session.states["a1.jpg"] == .heldNotSure(a))
        #expect(s.session.states["a1.jpg"]?.isNotSure == true)
    }

    @Test func deleteLeavesNoReferenceToTheDeletedCategory() async throws {
        let s = try fixture().service
        s.move(["u2.jpg"], to: catA.id)
        // b1 has A as its second guess; u1 and u3 have A as their best guess.
        #expect(s.session.states.values.contains { Self.references($0, catA.id) })
        s.delete(catA.id)
        let remaining = Set([catB.id, catC.id])
        func check() {
            for (id, state) in s.session.states {
                #expect(!Self.references(state, catA.id), "\(id): \(state)")
                if case .heldNotSure(let a) = state { #expect(remaining.contains(a.categoryID), "\(id)") }
            }
        }
        check()
        await s.settled()
        check()
    }

    @Test func deleteLastCategoryIsIgnored() async throws {
        let s = try fixture().service
        #expect(s.canDeleteCategory)
        s.delete(catB.id)
        s.delete(catC.id)
        await s.settled()
        #expect(!s.canDeleteCategory)
        let before = s.session
        let undoSteps = { var n = 0; while s.canUndo { s.undo(); n += 1 }; return n }
        s.delete(catA.id)
        #expect(s.session == before)
        #expect(s.session.categories.map(\.id) == [catA.id])
        await s.settled()
        #expect(s.session == before)
        #expect(undoSteps() == 2)  // Only the 2 real deletes.
    }

    private static func references(_ state: PhotoState, _ c: CategoryID) -> Bool {
        switch state {
        case .manual(let id): id == c
        case .auto(let a), .heldNotSure(let a): a.categoryID == c || a.secondCategoryID == c
        default: false
        }
    }

    // MARK: - Undo

    @Test func undoRestoresStatesAndCategories() async throws {
        let s = try fixture().service
        let original = s.session
        s.move(["u1.jpg"], to: catB.id)
        s.delete(catA.id)
        s.undo()
        #expect(category(catA.id, s) != nil)
        #expect(s.session.states["u1.jpg"] == .manual(catB.id))
        s.undo()
        #expect(s.session.categories == original.categories)
        #expect(s.session.states == original.states)
        #expect(!s.canUndo)
        #expect(s.canRedo)
        await s.settled()
        #expect(s.session.states == original.states)
        s.undo()  // Nothing left: no change.
        #expect(s.session.states == original.states)
    }

    @Test func redoAfterUndo() async throws {
        let s = try fixture().service
        s.move(["u1.jpg"], to: catB.id)
        await s.settled()
        let after = s.session
        s.undo()
        #expect(s.canRedo)
        s.redo()
        #expect(!s.canRedo)
        #expect(s.canUndo)
        await s.settled()
        #expect(s.session == after)

        s.undo()
        s.dontMove(["a1.jpg"])  // A new action clears the redo stack.
        #expect(!s.canRedo)
        s.redo()
        #expect(s.session.states["u1.jpg"] != .manual(catB.id))
        await s.settled()
    }

    @Test func undoStackKeeps100Changes() async throws {
        let s = try fixture().service
        for i in 0..<105 { s.rename(catA.id, to: "Name \(i)") }
        var undone = 0
        while s.canUndo { s.undo(); undone += 1 }
        #expect(undone == 100)
        #expect(category(catA.id, s)?.displayName == "Name 4")
        await s.settled()
    }

    // MARK: - Views

    @Test func countsMatchStates() async throws {
        let s = try fixture().service
        s.move(["u1.jpg"], to: catB.id)
        s.dontMove(["a2.jpg"])
        await s.settled()
        let c = s.counts()
        #expect(c.all == 8)
        #expect(c.videos == 1)
        #expect(c.unreadable == 1)
        #expect(c.dontMove == 1)
        #expect(c.changedByYou == 1)
        var shown: [CategoryID: Int] = [catA.id: 0, catB.id: 0, catC.id: 0]
        var notSure = 0
        for state in s.session.states.values {
            switch state {
            case .manual(let id): shown[id, default: 0] += 1
            case .auto(let a) where !a.uncertain: shown[a.categoryID, default: 0] += 1
            default: break
            }
            if state.isNotSure { notSure += 1 }
        }
        #expect(c.perCategory == shown)
        #expect(c.notSure == notSure)
    }

    @Test func notSureGroupsLargestFirst() throws {
        let s = try fixture().service
        let groups = s.notSureGroups
        try #require(groups.map(\.category) == [catA.id, catB.id])
        #expect(groups[0].ids == ["u1.jpg", "u3.jpg"])
        #expect(groups[1].ids == ["u2.jpg"])
    }

    @Test func notSureGroupTiesFollowCategoryOrder() throws {
        let s = try fixture().service
        s.acceptBestGuess(["u3.jpg"])
        s.reorder([catB.id, catA.id, catC.id])
        #expect(s.notSureGroups.map(\.category) == [catB.id, catA.id])
    }

    // MARK: - Background work

    @Test func rapidChangesSettleToTheLatestInputs() async throws {
        let f = try fixture()
        let s = f.service
        s.move(["u1.jpg"], to: catB.id)
        s.move(["u1.jpg"], to: catA.id)
        s.move(["u2.jpg"], to: catC.id)
        s.undo()
        await s.settled()
        // The first move would pull u2 and u3 into B. The final inputs pull them into A instead,
        // so a stale result applied after a newer change fails here.
        #expect(s.session.states["u1.jpg"] == .manual(catA.id))
        #expect(category(catA.id, s)?.exampleIDs == ["u1.jpg"])
        #expect(category(catB.id, s)?.exampleIDs == [])
        #expect(category(catC.id, s)?.exampleIDs == [])
        for id in ["u2.jpg", "u3.jpg"] {
            guard case .auto(let a)? = s.session.states[id] else { Issue.record("\(id) is not auto"); continue }
            #expect(a.categoryID == catA.id, "\(id)")
            #expect(!a.uncertain, "\(id)")
        }
        #expect(assignment("b1.jpg", s)?.categoryID == catB.id)
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    // MARK: - Move to Trash

    /// A fixture with fake file operations where every fixture photo exists under `source`.
    private func fakeFixture(failTrash: Set<String> = []) throws -> (f: Fixture, ops: FakeTrashOps) {
        let ops = FakeTrashOps(failTrash: failTrash)
        let f = try fixture(trash: TrashService(fileOps: ops))
        for name in Self.images.keys.sorted() + ["x1.jpg", "v1.mov"] { ops.add(f.source.appending(path: name)) }
        return (f, ops)
    }

    /// A fixture with 1 extra photo that is a real file with a unique name, for tests that use the real
    /// Trash. The unique name makes sure the Trash entry of the test is never another file's entry.
    private func realFixture(bytes: Data) throws -> (f: Fixture, id: MediaID, url: URL) {
        let id = "trash-test-\(UUID().uuidString).jpg"
        let f = try fixture(extra: id)
        try FileManager.default.createDirectory(at: f.source, withIntermediateDirectories: true)
        let url = f.source.appending(path: id)
        try bytes.write(to: url)
        return (f, id, url)
    }

    /// Removes the Trash entry of `id` only while this test still owns it: the photo is still trashed in
    /// the test's session. After a good put back the entry is not the test's any more, so it stays.
    private func removeOwnTrashEntry(_ id: MediaID, _ s: ReviewService) {
        guard let t = s.session.trashed.first(where: { $0.mediaID == id }), !t.trashPath.isEmpty else { return }
        try? FileManager.default.removeItem(at: URL(filePath: t.trashPath))
    }

    /// Review Focus 3: `trashItem` throws. The photo stays, the error is returned, no undo step.
    @Test func trashFailureKeepsPhoto() async throws {
        let (f, ops) = try fakeFixture(failTrash: ["u1.jpg"])
        let s = f.service
        let before = s.session
        let errors = await s.moveToTrash(["u1.jpg"])
        await s.settled()
        #expect(errors == [.cannotTrash("u1.jpg", "The volume has no Trash.")])
        #expect(s.session == before)
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)
        #expect(ops.exists(f.source.appending(path: "u1.jpg")))
    }

    @Test func partialTrashFailureRecordsOnlyMovedPhotos() async throws {
        let (f, ops) = try fakeFixture(failTrash: ["u2.jpg"])
        let s = f.service
        let u2 = s.session.states["u2.jpg"]
        let errors = await s.moveToTrash(["u1.jpg", "u2.jpg", "u1.jpg", "nope.jpg"])
        await s.settled()
        #expect(errors.map { if case .cannotTrash(let id, _) = $0 { id } else { "" } } == ["u2.jpg"])
        #expect(s.session.trashed.map(\.mediaID) == ["u1.jpg"])
        #expect(s.session.states["u1.jpg"] == nil)
        #expect(s.session.states["u2.jpg"] == u2)
        #expect(ops.exists(f.source.appending(path: "u2.jpg")))
        #expect(ops.trashCount == 2)
        s.undo()
        await s.settled()
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)
    }

    /// Review Focus 5: a trashed photo leaves counts, Not sure groups, and the sort plan.
    @Test func trashedPhotoNotInPlanCountsOrGroups() async throws {
        let (f, _) = try fakeFixture()
        let s = f.service
        #expect(s.counts().all == 8)
        #expect(s.counts().videos == 1)
        #expect(s.notSureGroups.flatMap(\.ids).contains("u1.jpg"))

        let errors = await s.moveToTrash(["u1.jpg", "v1.mov"])
        await s.settled()

        #expect(errors.isEmpty)
        #expect(s.session.scan.media.contains { $0.id == "u1.jpg" })  // A rescan can still see it.
        #expect(s.session.trashedIDs == ["u1.jpg", "v1.mov"])
        #expect(!s.session.visibleMedia.contains { s.session.trashedIDs.contains($0.id) })
        #expect(s.session.visibleMedia.count == 6)
        let counts = s.counts()
        #expect(counts.all == 6)
        #expect(counts.videos == 0)
        #expect(counts.notSure == 2)
        #expect(!s.notSureGroups.flatMap(\.ids).contains("u1.jpg"))
        #expect(s.session.states["u1.jpg"] == nil)

        let dst = f.root.url.appending(path: "Sorted", directoryHint: .isDirectory)
        let plan = try SortPlanner().plan(
            s.session, source: f.source,
            options: SortOptions(destination: dst, mode: .copy, dateFolders: false, rename: false, notSureChoice: .notSureFolder),
            existingNames: { _ in [] })
        #expect(!plan.entries.contains { $0.mediaID == "u1.jpg" || $0.mediaID == "v1.mov" })
        #expect(plan.entries.count + plan.leftInSource == 6)
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    @Test func trashingAnExampleReclassifies() async throws {
        let (f, _) = try fakeFixture()
        let s = f.service
        s.move(["u1.jpg"], to: catB.id)
        await s.settled()
        #expect(assignment("u3.jpg", s)?.categoryID == catB.id)  // u3 is close to the example u1.

        _ = await s.moveToTrash(["u1.jpg"])
        #expect(category(catB.id, s)?.exampleIDs == [])
        await s.settled()
        #expect(assignment("u3.jpg", s)?.categoryID == catA.id)
        #expect(assignment("u3.jpg", s)?.uncertain == true)
        #expect(s.session.states["u1.jpg"] == nil)
    }

    /// Spec 3.3: ⌘Z puts the photo back, with its state and example place, and the bytes are the same.
    @Test func undoPutsTrashedPhotoBack() async throws {
        let bytes = Data((0..<200).map { UInt8($0 % 251) })
        let (f, id, url) = try realFixture(bytes: bytes)
        let s = f.service
        defer { removeOwnTrashEntry(id, s) }
        s.move([id], to: catB.id)
        await s.settled()

        let errors = await s.moveToTrash([id])
        let trashURL = URL(filePath: try #require(s.session.trashed.first).trashPath)
        #expect(errors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(s.session.states[id] == nil)
        #expect(category(catB.id, s)?.exampleIDs == [])

        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors.isEmpty)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(!FileManager.default.fileExists(atPath: trashURL.path))
        #expect(s.session.trashed.isEmpty)
        #expect(s.session.states[id] == .manual(catB.id))
        #expect(category(catB.id, s)?.exampleIDs == [id])
        #expect(s.canRedo)
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    /// Review Focus 2: the user emptied the Trash before ⌘Z. The photo stays trashed.
    @Test func undoAfterTrashEmptiedKeepsTrashed() async throws {
        let (f, id, url) = try realFixture(bytes: Data([1, 2, 3]))
        let s = f.service
        _ = await s.moveToTrash([id])
        let trashURL = URL(filePath: try #require(s.session.trashed.first).trashPath)
        try FileManager.default.removeItem(at: trashURL)  // Empty the Trash (the test owns this entry).

        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors.count == 1)
        guard case .cannotPutBack(id, _)? = s.lastUndoErrors.first else {
            Issue.record("errors: \(s.lastUndoErrors)"); return
        }
        #expect(s.session.trashedIDs == [id])
        #expect(s.session.states[id] == nil)
        #expect(s.counts().all == 8)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!s.canRedo)
        #expect(!s.canUndo)
    }

    /// Review Focus 2: a new file is at the original path. Undo does not overwrite it.
    @Test func undoRefusesWhenOriginalPathTaken() async throws {
        let (f, id, url) = try realFixture(bytes: Data([1, 2, 3]))
        let s = f.service
        defer { removeOwnTrashEntry(id, s) }  // The put back fails, so the test still owns the entry.
        _ = await s.moveToTrash([id])
        let trashURL = URL(filePath: try #require(s.session.trashed.first).trashPath)
        let newer = Data([9, 9, 9, 9])
        try newer.write(to: url)

        s.undo()
        await s.settled()
        guard case .cannotPutBack(id, _)? = s.lastUndoErrors.first else {
            Issue.record("errors: \(s.lastUndoErrors)"); return
        }
        #expect(try Data(contentsOf: url) == newer)
        #expect(try Data(contentsOf: trashURL) == Data([1, 2, 3]))
        #expect(s.session.trashedIDs == [id])
        #expect(s.session.states[id] == nil)
    }

    /// `trashItem` gave no Trash URL: the file is in the Trash, so the photo is trashed. Undo cannot find
    /// the file and reports it.
    @Test func trashWithUnknownTrashURLIsRecordedAsTrashed() async throws {
        let ops = FakeTrashOps(noTrashURL: ["u1.jpg"])
        let f = try fixture(trash: TrashService(fileOps: ops))
        ops.add(f.source.appending(path: "u1.jpg"))
        let s = f.service
        let errors = await s.moveToTrash(["u1.jpg"])
        #expect(errors.isEmpty)
        #expect(s.session.trashed.map(\.trashPath) == [""])
        #expect(s.session.states["u1.jpg"] == nil)
        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors == [.cannotPutBack("u1.jpg", TrashService.unknownReason)])
        #expect(s.session.trashedIDs == ["u1.jpg"])
    }

    /// A second Move to Trash of a photo whose move is still running skips it: no false error.
    @Test func secondMoveToTrashOfSamePhotoIsSkipped() async throws {
        let (f, ops) = try fakeFixture()
        let s = f.service
        async let first = s.moveToTrash(["u1.jpg"])
        async let second = s.moveToTrash(["u1.jpg"])
        let errors = await first + second
        await s.settled()
        #expect(errors.isEmpty)
        #expect(ops.trashCount == 1)
        #expect(s.session.trashedIDs == ["u1.jpg"])
        #expect(s.session.trashed.count == 1)
    }

    @Test func redoTrashesAgain() async throws {
        let (f, ops) = try fakeFixture()
        let s = f.service
        let a2 = s.session.states["a2.jpg"]
        _ = await s.moveToTrash(["a2.jpg"])
        s.undo()
        await s.settled()
        #expect(s.session.states["a2.jpg"] == a2)
        #expect(ops.exists(f.source.appending(path: "a2.jpg")))

        s.redo()
        await s.settled()
        #expect(s.lastUndoErrors.isEmpty)
        #expect(s.session.trashedIDs == ["a2.jpg"])
        #expect(s.session.states["a2.jpg"] == nil)
        #expect(!ops.exists(f.source.appending(path: "a2.jpg")))
        #expect(s.canUndo)
        #expect(!s.canRedo)

        s.undo()
        await s.settled()
        #expect(s.session.trashed.isEmpty)
        #expect(s.session.states["a2.jpg"] == a2)
    }

    /// A photo that could not be put back stays trashed when an older step is undone.
    @Test func undoOfOlderStepKeepsFailedPhotoTrashed() async throws {
        let (f, ops) = try fakeFixture()
        let s = f.service
        s.move(["a2.jpg"], to: catB.id)
        _ = await s.moveToTrash(["a2.jpg"])
        ops.delete(URL(filePath: try #require(s.session.trashed.first).trashPath))  // Empty the Trash.
        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors.count == 1)
        #expect(s.canUndo)
        s.undo()  // Undoes the move. a2 must not come back.
        await s.settled()
        #expect(s.lastUndoErrors.isEmpty)
        #expect(s.session.states["a2.jpg"] == nil)
        #expect(s.session.categories.allSatisfy { !$0.exampleIDs.contains("a2.jpg") })
        #expect(s.session.trashedIDs == ["a2.jpg"])
    }

    /// A new action after a trash clears redo; a new trash clears redo too.
    @Test func moveToTrashClearsRedo() async throws {
        let (f, _) = try fakeFixture()
        let s = f.service
        s.dontMove(["a1.jpg"])
        s.undo()
        #expect(s.canRedo)
        _ = await s.moveToTrash(["b1.jpg"])
        #expect(!s.canRedo)
        #expect(s.canUndo)
    }

    @Test func openLoadsVectorsFromTheRepository() async throws {
        let root = try TempDir()
        let source = root.url.appending(path: "Photos", directoryHint: .isDirectory)
        let sessions = SessionRepository(root: root.url.appending(path: "Sessions", directoryHint: .isDirectory))
        var images: [String: Vector] = [:]
        for (id, v) in Self.images { images[id] = v }
        let embeddings = EmbeddingRepository(
            embedder: FakeEmbedder(dimension: 4, images: images, texts: Self.texts),
            cacheDirectory: sessions.directory(for: source))
        let session = makeSession(source: source)
        let s = try await ReviewService.open(
            session: session, source: source, embeddings: embeddings, classify: classify, sessions: sessions)
        #expect(s.session == session)
        s.move(["u1.jpg"], to: catB.id)
        await s.settled()
        #expect(assignment("u3.jpg", s)?.categoryID == catB.id)
        #expect(assignment("a2.jpg", s)?.categoryID == catA.id)
    }

    // MARK: - Suggestions

    /// A 6-dimensional session with categories A (e0) and B (e1), 1 certain A photo, and 2 groups of
    /// Not sure photos: 9 around e2 ("p") and 8 around e3 ("q"). The prompts of the first All topics
    /// candidate point at e2. The prompts of the Art studio candidate "Workshop event" point at e3. The
    /// session saved the old Everyday list. All files exist in fake file operations, for Move to Trash.
    private func suggestionFixture() throws -> (f: Fixture, first: Candidate) {
        func unit(_ v: Vector) -> Vector { VectorMath.normalize(v) }
        let all = try CandidateRepository().load(.all)
        let first = try #require(all.first)
        let workshop = try #require(all.first { $0.displayName == "Workshop event" })
        var texts: [String: Vector] = ["a": [1, 0, 0, 0, 0, 0], "b": [0, 1, 0, 0, 0, 0], "a photo of Sky": [0, 0, 0, 1, 0, 0]]
        for prompt in first.prompts { texts[prompt] = [0, 0, 1, 0, 0, 0] }
        for prompt in workshop.prompts { texts[prompt] = [0, 0, 0, 1, 0, 0] }
        var images: [MediaID: Vector] = ["a1.jpg": [1, 0, 0, 0, 0, 0]]
        for i in 1...9 { images["p\(i).jpg"] = unit([0, 0, 1, 0, 0.03 * Float(i), 0]) }
        for i in 1...8 { images["q\(i).jpg"] = unit([0, 0, 0, 1, 0, 0.03 * Float(i)]) }

        let root = try TempDir()
        let source = root.url.appending(path: "Photos", directoryHint: .isDirectory)
        let sessions = SessionRepository(root: root.url.appending(path: "Sessions", directoryHint: .isDirectory))
        let embeddings = EmbeddingRepository(
            embedder: FakeEmbedder(dimension: 6, texts: texts), cacheDirectory: sessions.directory(for: source))
        let ops = FakeTrashOps()
        for id in images.keys { ops.add(source.appending(path: id)) }
        let categories = [catA, catB]
        let prompts: [CategoryID: [Vector]] = [catA.id: [texts["a"]!], catB.id: [texts["b"]!]]
        let states = classify.classify(states: [:], categories: categories, images: images, prompts: prompts)
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: categories,
            states: states, scan: ScanResult(media: images.keys.sorted().map { media($0) }, dates: [:], skipped: [:]),
            sortedAt: nil)
        let service = ReviewService(
            session: session, source: source, images: images, prompts: prompts, classify: classify,
            sessions: sessions, embeddings: embeddings, trash: TrashService(fileOps: ops),
            candidates: CandidateRepository())
        return (Fixture(service: service, root: root, source: source, sessions: sessions), first)
    }

    @Test func suggestCategoriesNamesNotSureGroups() async throws {
        let (f, first) = try suggestionFixture()
        let s = f.service
        #expect(s.counts().notSure == 17)
        let suggestions = try await s.suggestCategories()
        let workshop = try #require(try CandidateRepository().load(.all).first { $0.displayName == "Workshop event" })
        try #require(suggestions.map(\.name) == [first.displayName, "Workshop event"])
        #expect(suggestions.map(\.emoji) == [first.emoji, workshop.emoji])
        try #require(suggestions.map(\.prompts) == [first.prompts, workshop.prompts])
        #expect(suggestions[0].ids == (1...9).map { "p\($0).jpg" })
        #expect(suggestions[1].ids == (1...8).map { "q\($0).jpg" })
    }

    /// Phase 12: suggestions use All topics, also for a session saved with the old Everyday list.
    @Test func suggestionsUseAllListForOldSession() async throws {
        let (f, _) = try suggestionFixture()
        #expect(f.service.session.candidateList == .everyday)
        #expect(try !CandidateRepository().load(.everyday).contains { $0.displayName == "Workshop event" })
        let suggestions = try await f.service.suggestCategories()
        let art = try #require(suggestions.first { $0.ids.contains("q1.jpg") })
        #expect(art.name == "Workshop event")
        #expect(!suggestions.contains { $0.name.hasPrefix("Group ") })
    }

    /// Spec 3.7: Add <N> Categories is 1 undo step. The photos become manual picks and examples.
    @Test func addSuggestedIsOneUndoStep() async throws {
        let (f, first) = try suggestionFixture()
        let s = f.service
        let before = s.session
        var suggestions = try await s.suggestCategories()
        try #require(suggestions.count == 2)
        // The second 1 as a "Group <n>" that the user renamed: no prompts, the folder emoji.
        suggestions[1].name = "Sky"
        suggestions[1].emoji = "📁"
        suggestions[1].prompts = []
        let added = s.addSuggested(suggestions)

        let categories = s.session.categories
        #expect(categories.map(\.displayName) == ["A", "B", first.displayName, "Sky"])
        try #require(categories.map(\.order) == [0, 1, 2, 3])
        #expect(categories.suffix(2).map(\.id) == added)
        #expect(categories[2].emoji == first.emoji)
        #expect(categories[2].prompts == first.prompts)
        #expect(categories[3].emoji == "📁")
        #expect(categories[3].prompts == ["a photo of Sky"])
        for (suggestion, category) in zip(suggestions, categories.suffix(2)) {
            #expect(category.exampleIDs == suggestion.ids)
            for id in suggestion.ids { #expect(s.session.states[id] == .manual(category.id)) }
        }
        await s.settled()
        #expect(s.counts().notSure == 0)
        #expect(try f.sessions.load(source: f.source) == s.session)

        s.undo()
        await s.settled()
        #expect(s.session.categories == before.categories)
        #expect(s.session.states == before.states)
        #expect(!s.canUndo)
        #expect(s.canRedo)
    }

    /// Review Focus 5: trashed photos are never in a suggestion.
    @Test func trashedPhotosAreNotSuggested() async throws {
        let (f, _) = try suggestionFixture()
        let s = f.service
        let errors = await s.moveToTrash(["p1.jpg", "q2.jpg"])
        await s.settled()
        #expect(errors.isEmpty)
        let ids = try await s.suggestCategories().flatMap(\.ids)
        #expect(ids.count == 15)
        #expect(!ids.contains("p1.jpg"))
        #expect(!ids.contains("q2.jpg"))
    }

    /// Spec 4.7: a photo the user moved, marked Don't Move, or trashed after the suggestion keeps its state.
    @Test func addSuggestedSkipsPhotosChangedSinceTheSuggestion() async throws {
        let (f, _) = try suggestionFixture()
        let s = f.service
        let suggestions = try await s.suggestCategories()
        try #require(suggestions.first?.ids.contains("p1.jpg") == true)
        let errors = await s.moveToTrash(["p3.jpg"])
        #expect(errors.isEmpty)
        await s.settled()
        // No wait here: after the recalculation, the example p1 would make the other p photos certain A.
        s.move(["p1.jpg"], to: catA.id)
        s.dontMove(["p2.jpg"])

        let added = s.addSuggested(suggestions)
        try #require(added.count == 2)
        let first = try #require(category(added[0], s))
        #expect(first.exampleIDs == (4...9).map { "p\($0).jpg" })
        #expect(s.session.states["p1.jpg"] == .manual(catA.id))
        #expect(category(catA.id, s)?.exampleIDs.contains("p1.jpg") == true)
        #expect(s.session.states["p2.jpg"] == .dontMove)
        #expect(s.session.states["p3.jpg"] == nil)
        #expect(s.session.trashedIDs.contains("p3.jpg"))
        await s.settled()
        #expect(s.session.states["p1.jpg"] == .manual(catA.id))
        #expect(s.session.states["p2.jpg"] == .dontMove)
    }

    @Test func suggestionWithNoPhotoLeftMakesNoCategory() async throws {
        let (f, first) = try suggestionFixture()
        let s = f.service
        let suggestions = try await s.suggestCategories()
        try #require(suggestions.count == 2)
        s.dontMove(suggestions[1].ids)
        let added = s.addSuggested(suggestions)
        #expect(added.count == 1)
        #expect(s.session.categories.map(\.displayName) == ["A", "B", first.displayName])

        let before = s.session
        #expect(s.addSuggested([suggestions[1]]).isEmpty)
        #expect(s.session == before)
    }

    @Test func photoInTwoSuggestionsGoesToTheFirst() async throws {
        let (f, _) = try suggestionFixture()
        let s = f.service
        let added = s.addSuggested([
            CategorySuggestion(name: "One", emoji: "1️⃣", prompts: [], ids: ["p1.jpg", "p2.jpg"]),
            CategorySuggestion(name: "Two", emoji: "2️⃣", prompts: [], ids: ["p2.jpg", "p3.jpg"]),
        ])
        try #require(added.count == 2)
        #expect(s.session.states["p2.jpg"] == .manual(added[0]))
        #expect(category(added[0], s)?.exampleIDs == ["p1.jpg", "p2.jpg"])
        #expect(category(added[1], s)?.exampleIDs == ["p3.jpg"])
    }

    // MARK: - Duplicates

    /// Real files under `source` for the hash and pixel-size reads; the Trash is fake.
    /// p1, p2: exact copies (64 px). q (32 px), r (48 px): similar. v.mov: a video with the bytes of p1.
    /// x.jpg: unreadable, with the bytes of p1 and the vector of q. gone.jpg: in the session with the
    /// vector of q, but not on disk (its pixel size cannot be read).
    /// `exactNearR`: p1 and p2 get the vector of r, so the similar search makes 1 group [p1, r, q] with the
    /// exact Keep photo p1 in it.
    /// `hashGate`: each file hash passes it, so a test can hold the hashing.
    private func duplicateFixture(
        exactNearR: Bool = false, hashGate: Gate? = nil
    ) throws -> (f: Fixture, ops: FakeTrashOps) {
        let root = try TempDir()
        let source = root.url.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let sessions = SessionRepository(root: root.url.appending(path: "Sessions", directoryHint: .isDirectory))
        let p1 = source.appending(path: "p1.jpg")
        try TestImages.writeJPEG(to: p1, color: (200, 10, 10), size: 64)
        for copy in ["p2.jpg", "v.mov", "x.jpg"] {
            try FileManager.default.copyItem(at: p1, to: source.appending(path: copy))
        }
        try TestImages.writeJPEG(to: source.appending(path: "q.jpg"), color: (10, 10, 200), size: 32)
        try TestImages.writeJPEG(to: source.appending(path: "r.jpg"), color: (10, 200, 10), size: 48)
        let names = ["p1.jpg", "p2.jpg", "q.jpg", "r.jpg", "v.mov", "x.jpg"]
        var files = try names.map { name in
            let url = source.appending(path: name)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return MediaFile(
                id: name, relativePath: name, kind: name.hasSuffix(".mov") ? .video : .image,
                size: Int64(values.fileSize ?? 0), modified: try #require(values.contentModificationDate))
        }
        files.append(MediaFile(id: "gone.jpg", relativePath: "gone.jpg", kind: .image, size: 1, modified: Date()))
        let q: Vector = [0, 1, 0, 0]
        let r: Vector = [0, 0.97, 0.2431, 0]
        let p: Vector = exactNearR ? r : [1, 0, 0, 0]
        let images: [MediaID: Vector] = [
            "p1.jpg": p, "p2.jpg": p, "q.jpg": q, "r.jpg": r, "x.jpg": q, "gone.jpg": q,
        ]
        let states: [MediaID: PhotoState] = [
            "p1.jpg": .dontMove, "p2.jpg": .dontMove, "q.jpg": .dontMove, "r.jpg": .dontMove, "x.jpg": .unreadable,
            "gone.jpg": .dontMove,
        ]
        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [catA],
            states: states, scan: ScanResult(media: files, dates: [:], skipped: [:]), sortedAt: nil)
        let ops = FakeTrashOps(files: names.map { source.appending(path: $0) })
        let embeddings = EmbeddingRepository(
            embedder: FakeEmbedder(dimension: 4, texts: Self.texts), cacheDirectory: sessions.directory(for: source))
        let service = ReviewService(
            session: session, source: source, images: images, prompts: [catA.id: [Self.texts["a"]!]],
            classify: classify, sessions: sessions, embeddings: embeddings, trash: TrashService(fileOps: ops),
            hashes: HashRepository(cacheDirectory: sessions.directory(for: source)) { url in
                hashGate?.pass()
                return HashRepository.sha256(of: url)
            },
            imageFiles: ImageRepository())
        return (Fixture(service: service, root: root, source: source, sessions: sessions), ops)
    }

    @Test func findDuplicatesFindsExactAndSimilar() async throws {
        let (f, _) = try duplicateFixture()
        let reports = Reports()
        let groups = try await f.service.findDuplicates { done, total in reports.add(done, total) }
        try #require(groups.map(\.kind) == [.exact, .similar])
        #expect(Set(groups[0].ids) == ["p1.jpg", "p2.jpg"])
        #expect(groups[0].keepIDs.count == 1)
        #expect(Set(groups[1].ids) == ["q.jpg", "r.jpg"])
        #expect(groups[1].keepIDs == ["r.jpg"])  // 48 px is more pixels than 32 px.
        #expect(reports.last.map { $0.done == $0.total } == true)
        #expect(FileManager.default.fileExists(
            atPath: f.sessions.directory(for: f.source).appending(path: "hashes.json").path))
    }

    @Test func videosAndUnreadableNotGrouped() async throws {
        let (f, _) = try duplicateFixture()
        let ids = try await f.service.findDuplicates().flatMap(\.ids)
        #expect(!ids.contains("v.mov"))
        #expect(!ids.contains("x.jpg"))
        #expect(!ids.contains("gone.jpg"))  // A missing file has no pixel size.
    }

    /// Review Focus 5: trashed photos are in no duplicate group.
    @Test func trashedPhotosNotGrouped() async throws {
        let (f, _) = try duplicateFixture()
        let s = f.service
        #expect(await s.moveToTrash(["p2.jpg", "q.jpg"]).isEmpty)
        await s.settled()
        #expect(try await s.findDuplicates().isEmpty)
    }

    @Test func dismissDuplicatesSavesTheKey() async throws {
        let (f, _) = try duplicateFixture()
        let s = f.service
        let groups = try await s.findDuplicates()
        let similar = try #require(groups.first { $0.kind == .similar })
        s.dismissDuplicates(similar)
        #expect(s.session.notDuplicateKeys == [similar.id])
        #expect(try f.sessions.load(source: f.source)?.notDuplicateKeys == [similar.id])
        #expect(try await s.findDuplicates().map(\.kind) == [.exact])
    }

    @Test func cleanUpTrashesNonKeepAndIsOneUndoStep() async throws {
        let (f, ops) = try duplicateFixture()
        let s = f.service
        let groups = try await s.findDuplicates()
        try #require(groups.count == 2)

        // A group with no Keep photo is refused.
        let noKeep = DuplicateGroup(kind: .similar, ids: ["p1.jpg", "r.jpg"], keepIDs: [])
        #expect(await s.cleanUp([noKeep]).isEmpty)
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)

        let keep = groups.reduce(into: Set<MediaID>()) { $0.formUnion($1.keepIDs) }
        let expected = Set(groups.flatMap(\.ids)).subtracting(keep)
        #expect(await s.cleanUp(groups).isEmpty)
        await s.settled()
        #expect(s.session.trashedIDs == expected)
        #expect(expected.count == 2)
        for id in keep { #expect(ops.exists(f.source.appending(path: id))) }
        for id in expected { #expect(!ops.exists(f.source.appending(path: id))) }

        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors.isEmpty)
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)  // The clean-up was 1 undo step.
        for id in expected { #expect(ops.exists(f.source.appending(path: id))) }
    }

    /// The Keep photo was trashed after the search: the stale groups trash nothing.
    @Test func cleanUpRefusesAGroupWhoseKeepPhotoIsGone() async throws {
        let (f, _) = try duplicateFixture()
        let s = f.service
        let groups = try await s.findDuplicates()
        try #require(groups.count == 2)
        let keeps = groups.flatMap(\.keepIDs)
        #expect(await s.moveToTrash(keeps).isEmpty)
        await s.settled()
        #expect(await s.cleanUp(groups).isEmpty)
        await s.settled()
        #expect(s.session.trashedIDs == Set(keeps))
    }

    /// The bytes of an exact copy changed after the search, with the same size and modification time:
    /// clean-up hashes the files again without the cache and keeps that photo.
    @Test func cleanUpKeepsAnExactCopyWhoseBytesChanged() async throws {
        let (f, _) = try duplicateFixture()
        let s = f.service
        let groups = try await s.findDuplicates()
        let exact = try #require(groups.first { $0.kind == .exact })
        let keep = try #require(exact.keepIDs.first)
        let other = try #require(exact.ids.first { $0 != keep })
        let url = f.source.appending(path: other)
        let modified = try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        // The cache still holds the old hash for the old key.
        #expect(try await s.findDuplicates().contains { $0.kind == .exact })

        #expect(await s.cleanUp([exact]).isEmpty)
        await s.settled()
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)
    }

    /// The found similar group S holds the Keep photo K of the exact group E (fixture `exactNearR`). The
    /// user marked r as Keep and unmarked K. Clean-up never trashes K, even when the caller dropped it
    /// from S's Keep photos.
    private func exactKeepInSimilarGroup(_ s: ReviewService) async throws -> (e: DuplicateGroup, s: DuplicateGroup, k: MediaID) {
        let groups = try await s.findDuplicates()
        let e = try #require(groups.first { $0.kind == .exact })
        let k = try #require(e.ids.first)
        var similar = try #require(groups.first { $0.kind == .similar })
        try #require(Set(similar.ids) == [k, "r.jpg", "q.jpg"])
        similar.keepIDs = ["r.jpg"]
        return (e, similar, k)
    }

    @Test func cleanUpOfExactThenSimilarKeepsTheExactKeepPhoto() async throws {
        let (f, ops) = try duplicateFixture(exactNearR: true)
        let s = f.service
        let (e, similar, k) = try await exactKeepInSimilarGroup(s)
        #expect(await s.cleanUp([e]).isEmpty)
        #expect(await s.cleanUp([similar]).isEmpty)
        await s.settled()
        #expect(!s.session.trashedIDs.contains(k))
        #expect(ops.exists(f.source.appending(path: k)))
        #expect(s.session.trashedIDs == Set(e.ids).subtracting([k]).union(["q.jpg"]))
    }

    @Test func cleanUpOfSimilarAloneKeepsTheExactKeepPhoto() async throws {
        let (f, _) = try duplicateFixture(exactNearR: true)
        let s = f.service
        let (_, similar, k) = try await exactKeepInSimilarGroup(s)
        #expect(await s.cleanUp([similar]).isEmpty)
        await s.settled()
        #expect(s.session.trashedIDs == ["q.jpg"])
        // The user can still trash it with Move to Trash.
        #expect(await s.moveToTrash([k]).isEmpty)
        #expect(s.session.trashedIDs.contains(k))
    }

    @Test func cleanUpNeverTrashesAKeepPhoto() async throws {
        let (f, _) = try duplicateFixture(exactNearR: true)
        let s = f.service
        try #require(try await s.findDuplicates().contains { Set($0.ids) == ["p1.jpg", "q.jpg", "r.jpg"] })
        // q is Keep in 1 group and not Keep in another: it stays. Both are parts of the found group.
        let groups = [
            DuplicateGroup(kind: .similar, ids: ["q.jpg", "r.jpg"], keepIDs: ["q.jpg"]),
            DuplicateGroup(kind: .similar, ids: ["q.jpg", "p1.jpg"], keepIDs: ["p1.jpg"]),
        ]
        #expect(await s.cleanUp(groups).isEmpty)
        await s.settled()
        #expect(s.session.trashedIDs == ["r.jpg"])
    }

    /// Controller note 1 (Task 27): clean-up acts only on the groups of the latest search. A group that is
    /// not a part of a found group of the same kind trashes nothing.
    @Test func cleanUpIgnoresAGroupNotInTheLatestResult() async throws {
        let (f, _) = try duplicateFixture()
        let s = f.service
        let made = DuplicateGroup(kind: .similar, ids: ["q.jpg", "r.jpg"], keepIDs: ["r.jpg"])
        #expect(await s.cleanUp([made]).isEmpty)  // No search yet.
        let groups = try await s.findDuplicates()
        try #require(groups.contains { $0.id == made.id })
        let other = DuplicateGroup(kind: .similar, ids: ["p1.jpg", "r.jpg"], keepIDs: ["p1.jpg"])
        let wrongKind = DuplicateGroup(kind: .exact, ids: ["q.jpg", "r.jpg"], keepIDs: ["q.jpg"])
        #expect(await s.cleanUp([other, wrongKind]).isEmpty)
        await s.settled()
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)
        // A found group with a Keep photo that the user changed is accepted.
        var toggled = try #require(groups.first { $0.id == made.id })
        toggled.keepIDs = ["q.jpg"]
        #expect(await s.cleanUp([toggled]).isEmpty)
        await s.settled()
        #expect(s.session.trashedIDs == ["r.jpg"])
    }

    /// The user moved the Keep of the exact group E from K to the other copy C. Then Clean Up All trashes K
    /// when K is not a Keep photo of any given group, and keeps K when a given group marks it Keep.
    @Test func cleanUpWithMovedExactKeepTrashesTheOldKeepOnlyWhenNotKeep() async throws {
        for markedInSimilar in [false, true] {
            let (f, _) = try duplicateFixture(exactNearR: true)
            let s = f.service
            let (e, similar, k) = try await exactKeepInSimilarGroup(s)  // similar: Keep r only.
            let c = try #require(e.ids.first { $0 != k })
            var moved = e
            moved.keepIDs = [c]
            var shown = similar
            if markedInSimilar { shown.keepIDs.insert(k) }
            #expect(await s.cleanUp([moved, shown], exactKeeps: [c]).isEmpty)
            await s.settled()
            #expect(s.session.trashedIDs == (markedInSimilar ? ["q.jpg"] : [k, "q.jpg"]), "\(markedInSimilar)")
            #expect(!s.session.trashedIDs.contains(c))
        }
    }

    /// The Keep K of the exact group E is not moved. No clean-up order trashes K, also when the given
    /// `exactKeeps` are wrong (they fall back to the original Keep photo).
    @Test func cleanUpNeverTrashesTheCurrentExactKeep() async throws {
        let orders: [(name: String, steps: [[DuplicateGroup.Kind]])] = [
            ("exact, similar", [[.exact], [.similar]]), ("similar, exact", [[.similar], [.exact]]),
            ("together", [[.exact, .similar]]),
        ]
        let keepSets: [Set<MediaID>?] = [nil, ["p1.jpg"], [], ["q.jpg"]]
        for order in orders {
            for exactKeeps in keepSets {
                let (f, _) = try duplicateFixture(exactNearR: true)
                let s = f.service
                let (e, similar, k) = try await exactKeepInSimilarGroup(s)  // similar: Keep r only.
                try #require(k == "p1.jpg")
                for step in order.steps {
                    let groups = step.map { $0 == .exact ? e : similar }
                    _ = await s.cleanUp(groups, exactKeeps: exactKeeps)
                    await s.settled()
                }
                #expect(!s.session.trashedIDs.contains(k), "\(order.name) \(String(describing: exactKeeps))")
                #expect(s.session.trashedIDs == ["p2.jpg", "q.jpg"], "\(order.name) \(String(describing: exactKeeps))")
            }
        }
    }

    @Test func findDuplicatesRecordsPixelSizes() async throws {
        let (f, _) = try duplicateFixture()
        let s = f.service
        #expect(s.pixelSize(of: "r.jpg") == nil)
        _ = try await s.findDuplicates()
        #expect(s.pixelSize(of: "r.jpg") == PixelSize(width: 48, height: 48))
        #expect(s.pixelSize(of: "p1.jpg") == PixelSize(width: 64, height: 64))
        #expect(s.pixelSize(of: "gone.jpg") == nil)
    }

    /// Review Focus 4: a group with the only example of a category. Clean-up removes it from
    /// `exampleIDs` and the photos are classified again.
    @Test func cleanUpRemovesExampleAndReclassifies() async throws {
        let (f, _) = try fakeFixture()
        let s = f.service
        s.move(["u1.jpg"], to: catB.id)
        await s.settled()
        #expect(category(catB.id, s)?.exampleIDs == ["u1.jpg"])
        #expect(assignment("u3.jpg", s)?.categoryID == catB.id)  // Close to the example u1.

        // Real files for u1 and u3 only, so the search makes the group [u3, u1] (u3 has more pixels).
        try FileManager.default.createDirectory(at: f.source, withIntermediateDirectories: true)
        try TestImages.writeJPEG(to: f.source.appending(path: "u3.jpg"), color: (10, 10, 200), size: 48)
        try TestImages.writeJPEG(to: f.source.appending(path: "u1.jpg"), color: (10, 200, 10), size: 32)
        let group = try #require(try await s.findDuplicates().first)
        try #require(group.ids == ["u3.jpg", "u1.jpg"] && group.keepIDs == ["u3.jpg"])
        #expect(await s.cleanUp([group]).isEmpty)
        await s.settled()
        #expect(s.session.trashedIDs == ["u1.jpg"])
        #expect(s.session.states["u1.jpg"] == nil)
        #expect(category(catB.id, s)?.exampleIDs == [])
        #expect(assignment("u3.jpg", s)?.categoryID == catA.id)  // Classified again without the example.
        #expect(try f.sessions.load(source: f.source) == s.session)
    }

    // MARK: - Final review fixes

    /// Final review I1: `settled()` waits for a clean-up that still hashes and moves files. `isMovingFiles`
    /// is true until the clean-up ends.
    @Test func settledWaitsForARunningCleanUp() async throws {
        let gate = Gate()
        let (f, _) = try duplicateFixture(hashGate: gate)
        let s = f.service
        let groups = try await s.findDuplicates()
        #expect(!s.isMovingFiles)
        gate.hold()
        let run = Task { await s.cleanUp(groups) }
        try await gate.untilWaiting()
        #expect(s.isMovingFiles)
        let waiter = Task { await s.settled(); return Date() }
        try await Task.sleep(for: .milliseconds(50))
        let released = Date()
        gate.release()
        #expect(await waiter.value >= released)
        #expect(s.session.trashed.count == 2)
        #expect(!s.isMovingFiles)
        #expect(await run.value.isEmpty)
    }

    /// Final review I1: `settled()` also waits for a Move to Trash that runs.
    @Test func settledWaitsForARunningMoveToTrash() async throws {
        let (f, ops) = try fakeFixture()
        let s = f.service
        ops.trashGate.hold()
        let run = Task { await s.moveToTrash(["u1.jpg"]) }
        try await ops.trashGate.untilWaiting()
        #expect(s.isMovingFiles)
        let waiter = Task { await s.settled(); return Date() }
        try await Task.sleep(for: .milliseconds(50))
        let released = Date()
        ops.trashGate.release()
        #expect(await waiter.value >= released)
        #expect(s.session.trashedIDs == ["u1.jpg"])
        #expect(!s.isMovingFiles)
        #expect(await run.value.isEmpty)
    }

    /// Final review I2: exact group {K, C} with the Keep moved to C; K is in a similar group, not as Keep.
    /// The user trashes C while clean-up hashes. Clean-up then protects K again, so 1 copy stays.
    @Test func cleanUpChecksTheExactKeepsAgainAfterHashing() async throws {
        let gate = Gate()
        let (f, ops) = try duplicateFixture(exactNearR: true, hashGate: gate)
        let s = f.service
        let (e, similar, k) = try await exactKeepInSimilarGroup(s)  // similar: Keep r only.
        let c = try #require(e.ids.first { $0 != k })
        var moved = e
        moved.keepIDs = [c]
        gate.hold()
        let run = Task { await s.cleanUp([moved, similar], exactKeeps: [c]) }
        try await gate.untilWaiting()
        #expect(await s.moveToTrash([c]).isEmpty)
        gate.release()
        #expect(await run.value.isEmpty)
        await s.settled()
        #expect(!s.session.trashedIDs.contains(k))
        #expect(ops.exists(f.source.appending(path: k)))
        #expect(s.session.trashedIDs == [c, "q.jpg"])
    }

    /// Final review I3: the Keep file of a similar group is gone from the disk (moved in Finder after the
    /// search). Clean-up trashes nothing of that group.
    @Test func cleanUpSkipsASimilarGroupWhoseKeepFileIsGone() async throws {
        let (f, ops) = try duplicateFixture()
        let s = f.service
        let similar = try #require(try await s.findDuplicates().first { $0.kind == .similar })
        try #require(similar.keepIDs == ["r.jpg"])
        ops.delete(f.source.appending(path: "r.jpg"))
        #expect(await s.cleanUp([similar]).isEmpty)
        await s.settled()
        #expect(s.session.trashed.isEmpty)
        #expect(!s.canUndo)
        #expect(ops.exists(f.source.appending(path: "q.jpg")))
    }

    /// Final review M1: an undo or redo that does nothing clears the errors of the last undo.
    @Test func undoOrRedoThatDoesNothingClearsOldErrors() async throws {
        let (f, ops) = try fakeFixture()
        let s = f.service
        #expect(await s.moveToTrash(["u1.jpg"]).isEmpty)
        let trashed = try #require(s.session.trashed.first)
        ops.delete(URL(filePath: trashed.trashPath))  // The user emptied the Trash.
        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors.count == 1)
        #expect(!s.canUndo && !s.canRedo)
        s.undo()
        #expect(s.lastUndoErrors.isEmpty)

        s.undo()
        await s.settled()
        #expect(await s.moveToTrash(["u2.jpg"]).isEmpty)
        let second = try #require(s.session.trashed.first { $0.mediaID == "u2.jpg" })
        ops.delete(URL(filePath: second.trashPath))
        s.undo()
        await s.settled()
        #expect(s.lastUndoErrors.count == 1)
        s.redo()
        #expect(s.lastUndoErrors.isEmpty)
    }

    // MARK: - Many Not sure (phase 11)

    /// A session of `images` images where the first `notSure` are held "Not sure" and the rest are manual.
    /// `trashed` are trashed photos; their states stay, so only the media list can leave them out.
    private func manyNotSureService(images: Int, notSure: Int, trashed: Set<MediaID>) throws -> ReviewService {
        let root = try TempDir()
        let source = root.url.appending(path: "Photos", directoryHint: .isDirectory)
        let sessions = SessionRepository(root: root.url.appending(path: "Sessions", directoryHint: .isDirectory))
        let ids = (0..<images).map { String(format: "p%03d.jpg", $0) }
        let held = Assignment(categoryID: catA.id, score: 0.1, secondCategoryID: nil, secondScore: nil,
                              percent: 50, uncertain: true)
        var states: [MediaID: PhotoState] = [:]
        for (i, id) in ids.enumerated() { states[id] = i < notSure ? .heldNotSure(held) : .manual(catA.id) }
        states["v1.mov"] = .heldNotSure(held)  // A video never counts.
        var session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: .everyday, categories: [catA],
            states: states, scan: ScanResult(media: ids.map { media($0) } + [media("v1.mov", .video)], dates: [:], skipped: [:]),
            sortedAt: nil)
        session.trashed = trashed.sorted().map { TrashedPhoto(mediaID: $0, trashPath: "/Trash/\($0)", time: Date()) }
        let embeddings = EmbeddingRepository(
            embedder: FakeEmbedder(dimension: 4, texts: Self.texts), cacheDirectory: sessions.directory(for: source))
        return ReviewService(
            session: session, source: source, images: [:], prompts: [catA.id: [Self.texts["a"]!]],
            classify: classify, sessions: sessions, embeddings: embeddings, trash: TrashService())
    }

    @Test func hasManyNotSureIgnoresTrashed() throws {
        #expect(try manyNotSureService(images: 200, notSure: 20, trashed: []).hasManyNotSure)
        #expect(!(try manyNotSureService(images: 201, notSure: 20, trashed: []).hasManyNotSure))
        // 1 trashed manual photo: 20 of 200 images left.
        #expect(try manyNotSureService(images: 201, notSure: 20, trashed: ["p200.jpg"]).hasManyNotSure)
        // 1 trashed "Not sure" photo: 19 left.
        #expect(!(try manyNotSureService(images: 100, notSure: 20, trashed: ["p000.jpg"]).hasManyNotSure))
    }

    /// Final review: 1 source of the "Not sure" counts for the Suggest sheet and the Sort hint.
    @Test func notSureImageCountsLeaveOutVideosAndTrashed() throws {
        let counts = try manyNotSureService(images: 201, notSure: 20, trashed: ["p000.jpg", "p200.jpg"])
            .session.notSureImageCounts
        #expect(counts.notSure == 19)
        #expect(counts.images == 199)
    }

    // MARK: - Close (Start Over)

    /// Final review: after `close()`, a review change does not write `session.json` (Start Over deleted it).
    @Test func closedServiceDoesNotSave() async throws {
        let f = try fixture()
        f.service.close()
        f.service.move(["u1.jpg"], to: catA.id)
        f.service.markSorted(at: Date(timeIntervalSince1970: 1_800_000_000))
        await f.service.settled()
        #expect(try f.sessions.load(source: f.source) == nil)
    }

    /// If the start over fails, `reopen()` saves the changes made while closed, and later changes save again.
    @Test func reopenSavesChangesMadeWhileClosed() async throws {
        let f = try fixture()
        f.service.close()
        f.service.move(["u1.jpg"], to: catA.id)
        await f.service.settled()
        f.service.reopen()
        #expect(try f.sessions.load(source: f.source) == f.service.session)

        f.service.move(["u2.jpg"], to: catA.id)
        await f.service.settled()
        #expect(try f.sessions.load(source: f.source)?.states["u2.jpg"] == .manual(catA.id))
    }

    @Test func reopenWithNoChangeDoesNotSave() throws {
        let f = try fixture()
        f.service.close()
        f.service.reopen()
        #expect(try f.sessions.load(source: f.source) == nil)
    }
}
