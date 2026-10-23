import Foundation
import Testing
@testable import PicnestCore

struct ScanServiceTests {
    private static let food: Vector = [1, 0, 0, 0]
    private static let pets: Vector = [0, 1, 0, 0]
    /// Prompt vectors for "Food" and "Pets" from the Everyday list. Other prompts embed to zero.
    private static let texts: [String: Vector] = [
        "a photo of a meal on a table": food,
        "a photo of food or drinks": VectorMath.normalize([0.9, 0, 0, 0.1]),
        "a photo of a pet dog or cat": pets,
    ]

    private func writePhotos(_ names: [String], in dir: URL) throws {
        for name in names {
            try TestImages.writeJPEG(to: dir.appending(path: name), color: (10, 20, 30))
        }
    }

    private func run(_ service: ScanService, source: URL) async throws -> (events: [ScanEvent], session: Session) {
        var events: [ScanEvent] = []
        var session: Session?
        for try await event in service.firstScan(source: source) {
            events.append(event)
            if case .finished(let s) = event { session = s }
        }
        return (events, try #require(session))
    }

    private func service(_ embedder: FakeEmbedder, sessions: URL) -> ScanService {
        ScanService(makeEmbedder: { embedder }, sessions: SessionRepository(root: sessions))
    }

    private func categoryID(of id: MediaID, in s: Session) -> CategoryID? {
        if case .auto(let a)? = s.states[id] { return a.categoryID }
        return nil
    }

    @Test func firstScanNamesClustersFromCandidates() async throws {
        let src = try TempDir(), root = try TempDir()
        let foodNames = (1...5).map { "food\($0).jpg" }
        let petNames = (1...3).map { "pet\($0).jpg" }
        try writePhotos(foodNames + petNames + ["broken.jpg"], in: src.url)
        try Data("not a video".utf8).write(to: src.url.appending(path: "clip.mov"))
        var images: [String: Vector] = [:]
        for n in foodNames { images[n] = Self.food }
        for n in petNames { images[n] = Self.pets }
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: Self.texts)

        let (events, session) = try await run(service(embedder, sessions: root.url), source: src.url)

        // Events: preparingModel, then embedding progress, then finished.
        guard case .preparingModel? = events.first else { Issue.record("first event: \(events)"); return }
        guard case .finished? = events.last else { Issue.record("last event: \(events)"); return }
        let progress = events.dropFirst().dropLast()
        #expect(!progress.isEmpty)
        for e in progress {
            guard case .embedding(_, let total) = e else { Issue.record("unexpected \(e)"); continue }
            #expect(total == 9)
        }

        let candidates = try CandidateRepository().load(.all)
        let foodCandidate = try #require(candidates.first { $0.displayName == "Food" })
        let petCandidate = try #require(candidates.first { $0.displayName == "Pets" })
        let cats = session.categories.sorted { $0.order < $1.order }
        #expect(cats.map(\.displayName) == ["Food", "Pets"])
        try #require(cats.map(\.order) == [0, 1])
        #expect(cats[0].emoji == foodCandidate.emoji)
        #expect(cats[0].prompts == foodCandidate.prompts)
        #expect(cats[1].emoji == petCandidate.emoji)
        #expect(cats[1].prompts == petCandidate.prompts)
        #expect(cats.allSatisfy { $0.exampleIDs.isEmpty })

        for n in foodNames {
            #expect(session.states[n] == .auto(Assignment(
                categoryID: cats[0].id, score: 1, secondCategoryID: cats[1].id, secondScore: 0,
                percent: 100, uncertain: false)))
        }
        for n in petNames { #expect(categoryID(of: n, in: session) == cats[1].id) }
        #expect(session.states["broken.jpg"] == .unreadable)
        #expect(session.states["clip.mov"] == nil)
        #expect(session.scan.media.count == 10)
        #expect(session.candidateList == .all)
        #expect(session.sortedAt == nil)

        // Saved, and found again by source.
        let saved = try SessionRepository(root: root.url).load(source: src.url)
        #expect(saved == session)
    }

    /// Phase 12: the first scan names clusters from All topics, so an art folder gets Art studio names.
    @Test func firstScanUsesAllList() async throws {
        let src = try TempDir(), root = try TempDir()
        let seaNames = (1...5).map { "sea\($0).jpg" }
        let foodNames = (1...4).map { "food\($0).jpg" }
        try writePhotos(seaNames + foodNames, in: src.url)
        var images: [String: Vector] = [:]
        for n in seaNames { images[n] = [0, 0, 1, 0] }
        for n in foodNames { images[n] = Self.food }
        var texts = Self.texts
        texts["a watercolor painting of the sea and boats"] = [0, 0, 1, 0]
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: texts)

        let (_, session) = try await run(service(embedder, sessions: root.url), source: src.url)

        #expect(session.candidateList == .all)
        #expect(session.categories.sorted { $0.order < $1.order }.map(\.displayName) == ["Artwork seascape", "Food"])
    }

    @Test func distinctNoisyPhotosFormTwoCategories() async throws {
        let src = try TempDir(), root = try TempDir()
        var rng = SplitMix64(seed: 11)
        var images: [String: Vector] = [:]
        func noisy(_ base: Vector) -> Vector {
            VectorMath.normalize(base.map { $0 + Float.random(in: -0.15...0.15, using: &rng) })
        }
        let foodNames = (1...10).map { "food\($0).jpg" }
        let petNames = (1...10).map { "pet\($0).jpg" }
        for n in foodNames { images[n] = noisy(Self.food) }
        for n in petNames { images[n] = noisy(Self.pets) }
        #expect(Set(images.values).count == 20)  // All distinct: no identical-vector collapse.
        try writePhotos(foodNames + petNames, in: src.url)
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: Self.texts)

        let (_, session) = try await run(service(embedder, sessions: root.url), source: src.url)

        #expect(Set(session.categories.map(\.displayName)) == ["Food", "Pets"])
        let food = try #require(session.categories.first { $0.displayName == "Food" })
        let pets = try #require(session.categories.first { $0.displayName == "Pets" })
        for n in foodNames { #expect(categoryID(of: n, in: session) == food.id) }
        for n in petNames { #expect(categoryID(of: n, in: session) == pets.id) }
    }

    @Test func duplicateCandidateClustersMerge() async throws {
        let src = try TempDir(), root = try TempDir()
        let near = (1...5).map { "near\($0).jpg" }
        let far = (1...3).map { "far\($0).jpg" }
        try writePhotos(near + far, in: src.url)
        var images: [String: Vector] = [:]
        for n in near { images[n] = Self.food }
        for n in far { images[n] = VectorMath.normalize([1, 0, 0.6, 0]) }  // Still closest to Food.
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: Self.texts)

        let (_, session) = try await run(service(embedder, sessions: root.url), source: src.url)

        try #require(session.categories.map(\.displayName) == ["Food"])
        let food = session.categories[0]
        for n in near + far {
            guard case .auto(let a)? = session.states[n] else { Issue.record("no state for \(n)"); continue }
            #expect(a.categoryID == food.id)
            #expect(a.secondCategoryID != food.id)
        }
    }

    @Test func firstScanWithNoPhotos() async throws {
        let src = try TempDir(), root = try TempDir()
        let embedder = FakeEmbedder(dimension: 4, texts: Self.texts)

        let (events, session) = try await run(service(embedder, sessions: root.url), source: src.url)

        #expect(session.categories.isEmpty)
        #expect(session.states.isEmpty)
        #expect(session.scan.media.isEmpty)
        guard case .preparingModel? = events.first else { Issue.record("first event: \(events)"); return }
        #expect(try SessionRepository(root: root.url).load(source: src.url) != nil)
    }

    private func rescan(_ service: ScanService, _ s: Session, source: URL) async throws -> (events: [ScanEvent], session: Session) {
        var events: [ScanEvent] = []
        var session: Session?
        for try await event in service.rescan(s, source: source) {
            events.append(event)
            if case .finished(let s) = event { session = s }
        }
        return (events, try #require(session))
    }

    @Test func rescanKeepsCategoriesAndManualPicks() async throws {
        let src = try TempDir(), root = try TempDir()
        let foodNames = (1...5).map { "food\($0).jpg" }
        let petNames = (1...3).map { "pet\($0).jpg" }
        try writePhotos(foodNames + petNames, in: src.url)
        var images: [String: Vector] = [:]
        for n in foodNames { images[n] = Self.food }
        for n in petNames + ["pet9.jpg"] { images[n] = Self.pets }
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: Self.texts)
        let service = service(embedder, sessions: root.url)
        var (_, session) = try await run(service, source: src.url)
        let food = try #require(session.categories.first { $0.displayName == "Food" })
        let pets = try #require(session.categories.first { $0.displayName == "Pets" })

        // The user renames Food, picks food1 and food2 by hand as Pets, and keeps food3 in place.
        let foodIndex = try #require(session.categories.firstIndex { $0.id == food.id })
        let petsIndex = try #require(session.categories.firstIndex { $0.id == pets.id })
        session.categories[foodIndex].displayName = "Meals"
        session.categories[foodIndex].emoji = "🍝"
        session.categories[petsIndex].exampleIDs = ["food1.jpg", "food2.jpg"]
        session.states["food1.jpg"] = .manual(pets.id)
        session.states["food2.jpg"] = .manual(pets.id)
        session.states["food3.jpg"] = .dontMove
        let held = Assignment(categoryID: pets.id, score: 0.1, secondCategoryID: nil, secondScore: nil, percent: 50, uncertain: true)
        session.states["food4.jpg"] = .heldNotSure(held)

        // Remove 1 manual pick, add 1 new photo and 1 file that cannot be read.
        try FileManager.default.removeItem(at: src.url.appending(path: "food2.jpg"))
        try writePhotos(["pet9.jpg", "bad.jpg"], in: src.url)
        let callsBefore = embedder.imageURLs.count

        let (events, after) = try await rescan(service, session, source: src.url)

        guard case .preparingModel? = events.first else { Issue.record("first event: \(events)"); return }
        guard case .finished? = events.last else { Issue.record("last event: \(events)"); return }
        // Only new files are embedded; unchanged files come from the cache.
        #expect(Set(embedder.imageURLs.dropFirst(callsBefore).map(\.lastPathComponent)) == ["pet9.jpg", "bad.jpg"])

        #expect(after.categories.map(\.id) == session.categories.map(\.id))
        #expect(after.categories.map(\.displayName) == session.categories.map(\.displayName))
        #expect(after.categories.map(\.emoji) == session.categories.map(\.emoji))
        #expect(after.categories.map(\.order) == session.categories.map(\.order))
        #expect(after.categories.map(\.prompts) == session.categories.map(\.prompts))
        #expect(after.states["food1.jpg"] == .manual(pets.id))
        #expect(after.states["food3.jpg"] == .dontMove)
        #expect(after.states["food4.jpg"] == .heldNotSure(held))
        #expect(after.states["food2.jpg"] == nil)
        #expect(!after.scan.media.contains { $0.id == "food2.jpg" })
        #expect(after.categories.allSatisfy { !$0.exampleIDs.contains("food2.jpg") })
        #expect(after.categories.first { $0.id == pets.id }?.exampleIDs == ["food1.jpg"])
        #expect(categoryID(of: "pet9.jpg", in: after) == pets.id)
        #expect(categoryID(of: "food5.jpg", in: after) == food.id)
        #expect(after.states["bad.jpg"] == .unreadable)
        #expect(after.candidateList == session.candidateList)
        #expect(try SessionRepository(root: root.url).load(source: src.url) == after)
    }

    @Test func rescanClassifiesChangedAndRecoveredFiles() async throws {
        let src = try TempDir(), root = try TempDir()
        try writePhotos(["food1.jpg", "food2.jpg", "pet1.jpg"], in: src.url)
        let embedder = FakeEmbedder(
            dimension: 4, images: ["food1.jpg": Self.food, "food2.jpg": Self.food, "pet1.jpg": Self.pets],
            texts: Self.texts)
        let service = service(embedder, sessions: root.url)
        var (_, session) = try await run(service, source: src.url)
        session.states["food2.jpg"] = .unreadable  // It was unreadable before; now it can be read.

        let (_, after) = try await rescan(service, session, source: src.url)

        guard case .auto? = after.states["food2.jpg"] else {
            Issue.record("food2: \(String(describing: after.states["food2.jpg"]))"); return
        }
        #expect(after.states["food1.jpg"] == session.states["food1.jpg"])
    }

    /// Marks a photo as trashed in the session, as `ReviewService.moveToTrash` does.
    private func markTrashed(_ id: MediaID, in s: inout Session) {
        s.states[id] = nil
        for i in s.categories.indices { s.categories[i].exampleIDs.removeAll { $0 == id } }
        s.trashed.append(TrashedPhoto(mediaID: id, trashPath: "/Trash/\(id)", time: Date()))
    }

    /// Spec 7.4: a trashed photo whose file is not at the original path leaves the session.
    @Test func rescanDropsTrashedWithMissingOriginal() async throws {
        let src = try TempDir(), root = try TempDir(), away = try TempDir()
        try writePhotos(["food1.jpg", "food2.jpg", "pet1.jpg"], in: src.url)
        let embedder = FakeEmbedder(
            dimension: 4, images: ["food1.jpg": Self.food, "food2.jpg": Self.food, "pet1.jpg": Self.pets],
            texts: Self.texts)
        let service = service(embedder, sessions: root.url)
        var (_, session) = try await run(service, source: src.url)
        markTrashed("food2.jpg", in: &session)
        try FileManager.default.moveItem(
            at: src.url.appending(path: "food2.jpg"), to: away.url.appending(path: "food2.jpg"))

        let (_, after) = try await rescan(service, session, source: src.url)

        #expect(after.trashed.isEmpty)
        #expect(!after.scan.media.contains { $0.id == "food2.jpg" })
        #expect(after.states["food2.jpg"] == nil)
        #expect(after.states["food1.jpg"] != nil)
        #expect(try SessionRepository(root: root.url).load(source: src.url) == after)
    }

    /// Spec 7.4: a photo put back with Finder comes back as a new photo.
    @Test func rescanRestoresPutBackPhoto() async throws {
        let src = try TempDir(), root = try TempDir()
        try writePhotos(["food1.jpg", "food2.jpg", "pet1.jpg"], in: src.url)
        let embedder = FakeEmbedder(
            dimension: 4, images: ["food1.jpg": Self.food, "food2.jpg": Self.food, "pet1.jpg": Self.pets],
            texts: Self.texts)
        let service = service(embedder, sessions: root.url)
        var (_, session) = try await run(service, source: src.url)
        let food = try #require(categoryID(of: "food1.jpg", in: session))
        markTrashed("food2.jpg", in: &session)  // The file is at its original path again.

        let (_, after) = try await rescan(service, session, source: src.url)

        #expect(after.trashed.isEmpty)
        #expect(after.scan.media.contains { $0.id == "food2.jpg" })
        #expect(categoryID(of: "food2.jpg", in: after) == food)
        #expect(after.trashedIDs.isEmpty)
    }

    /// Phase 11: a saved session with media but no categories (and no states). Rescan proposes
    /// categories as a first scan does, and every readable image gets a state. Don't move stays.
    @Test func rescanOfSessionWithNoCategoriesProposesCategories() async throws {
        let src = try TempDir(), root = try TempDir()
        let foodNames = (1...20).map { "food\($0).jpg" }
        let petNames = (1...10).map { "pet\($0).jpg" }
        try writePhotos(foodNames + petNames + ["bad.jpg"], in: src.url)
        var images: [String: Vector] = [:]
        for n in foodNames { images[n] = Self.food }
        for n in petNames { images[n] = Self.pets }
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: Self.texts)
        let service = service(embedder, sessions: root.url)
        var (_, session) = try await run(service, source: src.url)
        session.categories = []
        // Orphan states: they point to a category that no longer exists.
        let orphan = Assignment(categoryID: UUID(), score: 0.1, secondCategoryID: nil, secondScore: nil,
                                percent: 50, uncertain: true)
        session.states = ["food1.jpg": .dontMove, "pet1.jpg": .manual(UUID()), "pet2.jpg": .heldNotSure(orphan)]

        let (_, after) = try await rescan(service, session, source: src.url)

        #expect(after.categories.count > 0)
        #expect(Set(after.categories.map(\.displayName)) == ["Food", "Pets"])
        #expect(after.states["food1.jpg"] == .dontMove)
        #expect(after.states["bad.jpg"] == .unreadable)
        let readable = after.readableImages
        #expect(readable.count == 30)
        #expect(readable.allSatisfy { after.states[$0.id] != nil })
        let ids = Set(after.categories.map(\.id))
        let food = try #require(after.categories.first { $0.displayName == "Food" })
        for n in foodNames.dropFirst() { #expect(categoryID(of: n, in: after) == food.id, "\(n)") }
        for case .auto(let a) in after.states.values { #expect(ids.contains(a.categoryID)) }
        for n in ["pet1.jpg", "pet2.jpg"] {
            guard case .auto(let a)? = after.states[n] else { Issue.record("\(n) is \(String(describing: after.states[n]))"); continue }
            #expect(ids.contains(a.categoryID), "\(n)")
        }
        #expect(try SessionRepository(root: root.url).load(source: src.url) == after)
    }

    /// A session with categories is never clustered again: a new kind of photo gets no new category.
    @Test func rescanWithCategoriesStillNeverClusters() async throws {
        let src = try TempDir(), root = try TempDir()
        let foodNames = (1...5).map { "food\($0).jpg" }
        let petNames = (1...3).map { "pet\($0).jpg" }
        try writePhotos(foodNames + petNames, in: src.url)
        var images: [String: Vector] = [:]
        for n in foodNames { images[n] = Self.food }
        for n in petNames { images[n] = Self.pets }
        let embedder = FakeEmbedder(dimension: 4, images: images, texts: Self.texts)
        let service = service(embedder, sessions: root.url)
        var (_, session) = try await run(service, source: src.url)
        let food = try #require(session.categories.first { $0.displayName == "Food" })
        session.categories = [food]
        session.states = session.states.filter { petNames.contains($0.key) == false }

        let (_, after) = try await rescan(service, session, source: src.url)

        #expect(after.categories.map(\.id) == [food.id])
        for n in foodNames + petNames { #expect(after.states[n] != nil, "\(n)") }
    }

    @Test func embedderIsCreatedOnceAndErrorsEndTheStream() async throws {
        let src = try TempDir(), root = try TempDir()
        try writePhotos(["a.jpg"], in: src.url)
        let counter = Counter()
        let embedder = FakeEmbedder(dimension: 4, images: ["a.jpg": Self.food], texts: Self.texts)
        let service = ScanService(
            makeEmbedder: { counter.increment(); return embedder },
            sessions: SessionRepository(root: root.url))
        _ = try await run(service, source: src.url)
        _ = try await run(service, source: src.url)
        #expect(counter.value == 1)

        struct Boom: Error {}
        let failing = ScanService(makeEmbedder: { throw Boom() }, sessions: SessionRepository(root: root.url))
        await #expect(throws: Boom.self) { _ = try await run(failing, source: src.url) }
        let missing = src.url.appending(path: "nope", directoryHint: .isDirectory)
        await #expect(throws: (any Error).self) { _ = try await run(service, source: missing) }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
