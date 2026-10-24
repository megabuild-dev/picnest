import CryptoKit
import Foundation
import Testing
@testable import PicnestCore

// MARK: - Test file operations

/// Counts copies. Can throw on the Nth copy (after it writes a partial file), or report a wrong
/// size for files under a folder.
final class TestFileOps: FileOps, @unchecked Sendable {
    private let base = LocalFileOps()
    private let lock = NSLock()
    private var copyCount = 0
    let failOnCopy: Int?
    let wrongSizeUnder: String?

    /// Copy number `gateOnCopy` signals `reached`, then waits for `release` before it copies.
    let gateOnCopy: Int?
    let reached = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    init(failOnCopy: Int? = nil, wrongSizeUnder: URL? = nil, gateOnCopy: Int? = nil) {
        self.gateOnCopy = gateOnCopy
        self.failOnCopy = failOnCopy
        self.wrongSizeUnder = wrongSizeUnder?.standardizedFileURL.path
    }

    var copies: Int { lock.withLock { copyCount } }

    func exists(_ u: URL) -> Bool { base.exists(u) }
    func makeFolder(_ u: URL) throws { try base.makeFolder(u) }
    func copy(_ from: URL, _ to: URL) throws {
        let n = lock.withLock { copyCount += 1; return copyCount }
        if n == failOnCopy {
            try Data([1, 2, 3]).write(to: to)  // A partial file, as a full disk leaves it.
            throw CocoaError(.fileWriteOutOfSpace)
        }
        if n == gateOnCopy {
            reached.signal()
            release.wait()
        }
        try base.copy(from, to)
    }
    func size(_ u: URL) throws -> Int64 {
        let s = try base.size(u)
        if let w = wrongSizeUnder, u.standardizedFileURL.path.hasPrefix(w + "/") { return s + 1 }
        return s
    }
    func modified(_ u: URL) throws -> Date { try base.modified(u) }
    func remove(_ u: URL) throws { try base.remove(u) }
    func trash(_ u: URL) throws -> URL? { try base.trash(u) }
    func move(_ from: URL, _ to: URL) throws { try base.move(from, to) }
    func removeEmptyFolder(_ u: URL) throws { try base.removeEmptyFolder(u) }
    func isEmptyFolder(_ u: URL) -> Bool { base.isEmptyFolder(u) }

    /// Waits for the gated copy to start without blocking a Swift concurrency thread.
    func waitUntilGateReached() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { self.reached.wait(); c.resume() }
        }
    }
    func names(in folder: URL) -> Set<String> { base.names(in: folder) }
}

// MARK: - Fixture

struct SortFixture {
    let tmp: TempDir
    let source: URL
    let destination: URL
    let journal: JournalRepository
    let food = Category(id: UUID(), displayName: "Food", emoji: "", prompts: [], exampleIDs: [], order: 0)
    let pets = Category(id: UUID(), displayName: "Pets", emoji: "", prompts: [], exampleIDs: [], order: 1)

    /// Relative paths of the source files. Each one gets different random bytes.
    init(files: [String] = ["a.jpg", "b.jpg", "sub/c.jpg", "d.jpg", "e.jpg"]) throws {
        tmp = try TempDir()
        source = tmp.url.appending(path: "src", directoryHint: .isDirectory)
        destination = tmp.url.appending(path: "src - sorted", directoryHint: .isDirectory)
        journal = JournalRepository(directory: tmp.url.appending(path: "session", directoryHint: .isDirectory))
        for (i, f) in files.enumerated() {
            let url = source.appending(path: f, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((0..<(100 + i * 37)).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        }
    }

    /// A session where every file is a manual pick: even index → Food, odd index → Pets.
    func session() throws -> Session {
        let ops = LocalFileOps()
        var media: [MediaFile] = []
        var states: [MediaID: PhotoState] = [:]
        for (i, rel) in try Self.files(in: source).enumerated() {
            let nfc = rel.precomposedStringWithCanonicalMapping
            let url = source.appending(path: rel, directoryHint: .notDirectory)
            media.append(MediaFile(id: nfc, relativePath: nfc, kind: .image, size: try ops.size(url), modified: try ops.modified(url)))
            states[nfc] = .manual(i % 2 == 0 ? food.id : pets.id)
        }
        return Session(sourcePath: source.path, candidateList: .everyday, categories: [food, pets], states: states,
                       scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil)
    }

    func plan(_ service: SortService, mode: SortMode = .copy) throws -> SortPlan {
        let options = SortOptions(destination: destination, mode: mode, dateFolders: false, rename: false, notSureChoice: .acceptBestGuess)
        return try service.plan(try session(), source: source, options: options)
    }

    /// Relative file paths under a folder, sorted.
    static func files(in folder: URL) throws -> [String] {
        try snapshot(folder).keys.filter { !$0.hasSuffix("/") }.sorted()
    }

    /// Relative path → size and SHA-256 for files; folders end with "/". Empty if the folder does not exist.
    static func snapshot(_ folder: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [:] }
        var out: [String: String] = [:]
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [:] }
        for case let url as URL in e {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            let rel = String(path.dropFirst(root.count + 1))
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                out[rel + "/"] = "dir"
            } else {
                let data = try Data(contentsOf: url)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                out[rel] = "\(data.count) \(hash)"
            }
        }
        return out
    }
}

@discardableResult
func drain(_ stream: AsyncThrowingStream<SortEvent, Error>) async throws -> [SortEvent] {
    var events: [SortEvent] = []
    for try await e in stream { events.append(e) }
    return events
}

func sortError(_ body: () async throws -> Void) async -> SortError? {
    do { try await body(); return nil } catch let e as SortError { return e } catch { return nil }
}

func organizeError(_ body: () throws -> Void) -> SortError? {
    do { try body(); return nil } catch let e as SortError { return e } catch { return nil }
}

// MARK: - Tests

@Suite(.serialized)
struct SortServiceTests {
    @Test func copyThenUndoRestoresBothFolders() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try f.plan(service)
        let srcBefore = try SortFixture.snapshot(f.source)
        #expect(try SortFixture.snapshot(f.destination).isEmpty)

        let events = try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false }))
        guard case .finished(let copied, let moved)? = events.last else { Issue.record("no finished"); return }
        #expect(copied == 5 && moved == 0)
        #expect(try SortFixture.files(in: f.destination) == ["Food/a.jpg", "Food/c.jpg", "Food/d.jpg", "Pets/b.jpg", "Pets/e.jpg"])
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
        #expect(try f.journal.lastIsComplete() == true)

        try service.undo(journal: f.journal)
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        #expect(try f.journal.lastIsComplete() == nil)
    }

    @Test func moveThenUndoRestoresBothFolders() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try f.plan(service, mode: .move)
        let srcBefore = try SortFixture.snapshot(f.source)

        let events = try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { false }))
        guard case .finished(let copied, let moved)? = events.last else { Issue.record("no finished"); return }
        #expect(copied == 0 && moved == 5)
        #expect(try SortFixture.files(in: f.source).isEmpty)
        #expect(try SortFixture.files(in: f.destination).count == 5)

        try service.undo(journal: f.journal)
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
    }

    @Test func movedFilesKeepModificationDate() async throws {
        let f = try SortFixture(files: ["a.jpg"])
        let service = SortService()
        let plan = try f.plan(service, mode: .move)
        try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { false }))
        let entry = try #require(plan.entries.first)
        #expect(try LocalFileOps().modified(entry.destination) == entry.modified)
    }

    // MARK: - Organize in place (spec 7.2)

    @Test func organizeMovesFilesIntoCategoryFoldersWithoutJournal() async throws {
        let f = try SortFixture()
        let service = SortService()
        let before = try SortFixture.snapshot(f.source)
        let plan = try service.planInPlace(try f.session(), source: f.source)
        #expect(plan.entries.count == 5)

        let result = try service.organize(plan, source: f.source)
        #expect(result.failures.isEmpty)
        #expect(Set(result.moves.map(\.to)) == Set(try SortFixture.files(in: f.source)))
        // No journal: an organize cannot be undone.
        #expect(!f.journal.exists)
        #expect(try f.journal.lastIsComplete() == nil)
        // Every file left the root and is renamed, but no bytes changed.
        let files = try SortFixture.files(in: f.source)
        #expect(files.count == 5)
        #expect(files.filter { $0.hasPrefix("Food/") }.count == 3)
        #expect(files.filter { $0.hasPrefix("Pets/") }.count == 2)
        #expect(files.allSatisfy { $0.contains("_Food_") || $0.contains("_Pets_") })
        #expect(Set(try SortFixture.snapshot(f.source).values) == Set(before.values))
    }

    @Test func organizeStopsIfAFileChangedSinceScan() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try service.planInPlace(try f.session(), source: f.source)
        try Data(repeating: 7, count: 9999).write(to: f.source.appending(path: "b.jpg"))

        let error = organizeError { try service.organize(plan, source: f.source) }
        #expect(error == .changedSinceScan(["b.jpg"]))
        #expect(try SortFixture.files(in: f.source) == ["a.jpg", "b.jpg", "d.jpg", "e.jpg", "sub/c.jpg"])
    }

    @Test func organizeLeavesAnAlreadyOrganizedFolderAlone() async throws {
        let f = try SortFixture()
        let service = SortService()
        let first = try service.organize(try service.planInPlace(try f.session(), source: f.source), source: f.source)
        #expect(first.failures.isEmpty)

        // A session that matches the new layout: each file's folder is its category.
        let ops = LocalFileOps()
        var media: [MediaFile] = []
        var states: [MediaID: PhotoState] = [:]
        for rel in try SortFixture.files(in: f.source) {
            let url = f.source.appending(path: rel, directoryHint: .notDirectory)
            media.append(MediaFile(id: rel, relativePath: rel, kind: .image,
                                   size: try ops.size(url), modified: try ops.modified(url)))
            states[rel] = rel.hasPrefix("Food/") ? .manual(f.food.id) : .manual(f.pets.id)
        }
        let organized = Session(
            sourcePath: f.source.path, candidateList: .everyday, categories: [f.food, f.pets], states: states,
            scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil)
        #expect(try service.planInPlace(organized, source: f.source).entries.isEmpty)
    }

    @Test func stopsIfFileChangedSinceScan() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try f.plan(service)
        let changed = f.source.appending(path: "b.jpg")
        try Data(repeating: 7, count: 999).write(to: changed)

        let e = await sortError { try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false })) }
        #expect(e == .changedSinceScan(["b.jpg"]))
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        #expect(try f.journal.lastIsComplete() == nil)
    }

    @Test func stopsIfFileRemovedSinceScan() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try f.plan(service, mode: .move)
        try FileManager.default.removeItem(at: f.source.appending(path: "sub/c.jpg"))

        let e = await sortError { try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { false })) }
        #expect(e == .changedSinceScan(["sub/c.jpg"]))
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        #expect(try SortFixture.files(in: f.source).count == 4)
    }

    @Test func stopsIfDestinationAppeared() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try f.plan(service)
        let target = try #require(plan.entries.last).destination
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9]).write(to: target)

        let e = await sortError { try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false })) }
        #expect(e == .destinationExists([target]))
        #expect(try SortFixture.files(in: f.destination).count == 1)
        #expect(try Data(contentsOf: target) == Data([9]))
    }

    @Test func failedCopyCanBeUndone() async throws {
        let f = try SortFixture()
        let ops = TestFileOps(failOnCopy: 3)
        let service = SortService(fileOps: ops)
        let plan = try f.plan(service)
        let srcBefore = try SortFixture.snapshot(f.source)

        var thrown: Error?
        do { try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false })) } catch { thrown = error }
        #expect((thrown as? CocoaError)?.code == .fileWriteOutOfSpace)
        let entries = try f.journal.read()
        #expect(entries.filter { $0.op == .copy }.count == 2)
        #expect(!entries.contains { $0.op == .done })
        #expect(try f.journal.lastIsComplete() == false)
        #expect(try SortFixture.files(in: f.destination).count == 2)  // The partial third file is gone.

        try service.undo(journal: f.journal)
        #expect(try SortFixture.files(in: f.destination).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
    }

    @Test func failedMoveCanBeUndone() async throws {
        let f = try SortFixture()
        let ops = TestFileOps(failOnCopy: 4)
        let service = SortService(fileOps: ops)
        let plan = try f.plan(service, mode: .move)
        let srcBefore = try SortFixture.snapshot(f.source)

        await #expect(throws: CocoaError.self) { try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { false })) }
        #expect(try f.journal.read().filter { $0.op == .move }.count == 3)
        #expect(try SortFixture.files(in: f.source).count == 2)

        try service.undo(journal: f.journal)
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
    }

    @Test func refusesNewSortAfterUnfinishedSort() async throws {
        let f = try SortFixture()
        let service = SortService()
        let plan = try f.plan(service)
        try f.journal.append(JournalEntry(op: .mkdir, source: nil, destination: f.tmp.url.appending(path: "x").path, time: .now))

        let e = await sortError { try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false })) }
        #expect(e == .unfinishedLastSort)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        #expect(try f.journal.read().count == 1)
    }

    @Test func hasUnfinishedSortOnlyWithoutDoneLine() async throws {
        let f = try SortFixture()
        let service = SortService()
        #expect(!service.hasUnfinishedSort(journal: f.journal))
        try f.journal.append(JournalEntry(op: .mkdir, source: nil, destination: f.tmp.url.appending(path: "x").path, time: .now))
        #expect(service.hasUnfinishedSort(journal: f.journal))
        try f.journal.append(JournalEntry(op: .done, source: nil, destination: nil, time: .now))
        #expect(!service.hasUnfinishedSort(journal: f.journal))
    }

    @Test func completeJournalIsArchivedOnNextSort() async throws {
        let f = try SortFixture(files: ["a.jpg", "b.jpg"])
        let service = SortService()
        try await drain(service.run(try f.plan(service), mode: .copy, journal: f.journal, stop: { false }))
        // Second sort to another destination.
        let options = SortOptions(destination: f.tmp.url.appending(path: "second", directoryHint: .isDirectory), mode: .copy,
                                  dateFolders: false, rename: false, notSureChoice: .acceptBestGuess)
        let plan2 = try service.plan(try f.session(), source: f.source, options: options)
        try await drain(service.run(plan2, mode: .copy, journal: f.journal, stop: { false }))

        let names = try FileManager.default.contentsOfDirectory(atPath: f.journal.directory.path).sorted()
        #expect(names.count == 2)
        #expect(names.contains("journal.jsonl"))
        #expect(names.contains { $0.hasPrefix("journal.") && $0.hasSuffix(".jsonl") && $0 != "journal.jsonl" })
        // Undo reverses only the newest sort.
        try service.undo(journal: f.journal)
        #expect(!FileManager.default.fileExists(atPath: options.destination.path))
        #expect(try SortFixture.files(in: f.destination).count == 2)
    }

    @Test func sizeMismatchKeepsSource() async throws {
        let f = try SortFixture()
        let ops = TestFileOps(wrongSizeUnder: f.destination)
        let service = SortService(fileOps: ops)
        let plan = try f.plan(service, mode: .move)
        let first = try #require(plan.entries.first)

        let e = await sortError { try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { false })) }
        #expect(e == .sizeMismatch(first.destination))
        #expect(FileManager.default.fileExists(atPath: first.source.path))
        #expect(!FileManager.default.fileExists(atPath: first.destination.path))
        #expect(try SortFixture.files(in: f.source).count == 5)
        #expect(!(try f.journal.read()).contains { $0.op == .move || $0.op == .done })
    }

    @Test func stopWritesNoDone() async throws {
        let f = try SortFixture()
        let ops = TestFileOps()
        let service = SortService(fileOps: ops)
        let plan = try f.plan(service, mode: .move)
        let srcBefore = try SortFixture.snapshot(f.source)

        let e = await sortError { try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { ops.copies >= 2 })) }
        #expect(e == .stopped)
        #expect(ops.copies == 2)
        #expect(try f.journal.lastIsComplete() == false)
        #expect(try f.journal.read().filter { $0.op == .move }.count == 2)

        try service.undo(journal: f.journal)
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
    }

    @Test func cancellingTheConsumerStopsLikeStop() async throws {
        let f = try SortFixture()
        let ops = TestFileOps(gateOnCopy: 2)
        let service = SortService(fileOps: ops)
        let plan = try f.plan(service, mode: .move)
        let srcBefore = try SortFixture.snapshot(f.source)

        let stream = service.run(plan, mode: .move, journal: f.journal, stop: { false })
        let consumer = Task { for try await _ in stream {} }
        await ops.waitUntilGateReached()     // Copy 2 has started.
        consumer.cancel()
        _ = await consumer.result            // The stream ended, so the producer task is cancelled.
        ops.release.signal()                 // Copy 2 finishes; no copy 3 starts.
        await service.waitUntilIdle()

        #expect(ops.copies == 2)
        let entries = try f.journal.read()
        #expect(!entries.contains { $0.op == .done })
        #expect(entries.filter { $0.op == .move }.compactMap(\.source) == plan.entries.prefix(2).map(\.source.path))
        #expect(try SortFixture.files(in: f.source).count == 3)

        try service.undo(journal: f.journal)
        #expect(try SortFixture.snapshot(f.source) == srcBefore)
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
    }

    @Test func runOrUndoWhileActiveIsBusy() async throws {
        let f = try SortFixture()
        let ops = TestFileOps(gateOnCopy: 1)
        let service = SortService(fileOps: ops)
        let plan = try f.plan(service)

        let first = Task { try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false })) }
        await ops.waitUntilGateReached()
        let other = JournalRepository(directory: f.tmp.url.appending(path: "other", directoryHint: .isDirectory))
        let e = await sortError { try await drain(service.run(plan, mode: .copy, journal: other, stop: { false })) }
        #expect(e == .busy)
        #expect(throws: SortError.busy) { try service.undo(journal: f.journal) }
        #expect(try other.lastIsComplete() == nil)

        ops.release.signal()
        let events = try await first.value
        guard case .finished(let copied, _)? = events.last else { Issue.record("no finished"); return }
        #expect(copied == 5)
        await service.waitUntilIdle()
        try service.undo(journal: f.journal)  // Idle again: works.
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
    }

    @Test func vietnameseNamesSortAndUndo() async throws {
        let nfd = "hình ảnh/ảnh 1.jpg".decomposedStringWithCanonicalMapping
        let f = try SortFixture(files: [nfd, "ảnh 2.jpg".decomposedStringWithCanonicalMapping])
        let service = SortService()
        for mode in [SortMode.copy, .move] {
            let plan = try f.plan(service, mode: mode)
            let srcBefore = try SortFixture.snapshot(f.source)
            try await drain(service.run(plan, mode: mode, journal: f.journal, stop: { false }))
            #expect(try SortFixture.files(in: f.destination).count == 2)
            for entry in plan.entries { #expect(FileManager.default.fileExists(atPath: entry.destination.path)) }
            try service.undo(journal: f.journal)
            #expect(try SortFixture.snapshot(f.source) == srcBefore)
            #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        }
    }

    @Test func undoTwiceSaysNothingToUndo() async throws {
        let f = try SortFixture(files: ["a.jpg"])
        let service = SortService()
        try await drain(service.run(try f.plan(service), mode: .copy, journal: f.journal, stop: { false }))
        try service.undo(journal: f.journal)
        #expect(throws: SortError.nothingToUndo) { try service.undo(journal: f.journal) }
        #expect(try SortFixture.files(in: f.source) == ["a.jpg"])
    }

    @Test func undoMoveDoesNotOverwriteNewSourceFile() async throws {
        let f = try SortFixture(files: ["a.jpg", "b.jpg"])
        let service = SortService()
        let plan = try f.plan(service, mode: .move)
        try await drain(service.run(plan, mode: .move, journal: f.journal, stop: { false }))
        let a = try #require(plan.entries.first { $0.mediaID == "a.jpg" })
        try Data([42]).write(to: a.source)  // A new file appeared at the old place.

        #expect(throws: SortError.undoConflicts([a.destination])) { try service.undo(journal: f.journal) }
        #expect(try Data(contentsOf: a.source) == Data([42]))
        #expect(FileManager.default.fileExists(atPath: a.destination.path))  // Kept, not lost.
        #expect(try SortFixture.files(in: f.source) == ["a.jpg", "b.jpg"])
        #expect(try SortFixture.files(in: f.destination).count == 1)
        #expect(try f.journal.lastIsComplete() == nil)  // Archived.
    }

    @Test func undoCopyKeepsDestinationWhenSourceIsGone() async throws {
        let f = try SortFixture(files: ["a.jpg"])
        let service = SortService()
        let plan = try f.plan(service)
        try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false }))
        let a = try #require(plan.entries.first)
        try FileManager.default.removeItem(at: a.source)  // The user deleted the original.

        #expect(throws: SortError.undoConflicts([a.destination])) { try service.undo(journal: f.journal) }
        #expect(FileManager.default.fileExists(atPath: a.destination.path))  // The only copy is kept.
    }

    @Test func undoKeepsFolderWithNewFiles() async throws {
        let f = try SortFixture(files: ["a.jpg"])
        let service = SortService()
        let plan = try f.plan(service)
        try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false }))
        let folder = try #require(plan.entries.first).destination.deletingLastPathComponent()
        let mine = folder.appending(path: "mine.txt")
        try Data([1]).write(to: mine)

        try service.undo(journal: f.journal)
        #expect(FileManager.default.fileExists(atPath: mine.path))
        #expect(try SortFixture.files(in: f.destination) == ["Food/mine.txt"])
    }

    @Test func progressEventsCountFiles() async throws {
        let f = try SortFixture(files: ["a.jpg", "b.jpg", "c.jpg"])
        let service = SortService()
        let events = try await drain(service.run(try f.plan(service), mode: .copy, journal: f.journal, stop: { false }))
        let progress = events.compactMap { e -> Int? in if case .progress(let d, 3) = e { d } else { nil } }
        #expect(progress == [1, 2, 3])
    }

    @Test func journalStoresAbsolutePathsAndMkdirFirst() async throws {
        let f = try SortFixture(files: ["a.jpg"])
        let service = SortService()
        let plan = try f.plan(service)
        try await drain(service.run(plan, mode: .copy, journal: f.journal, stop: { false }))
        let entries = try f.journal.read()
        try #require(entries.map(\.op) == [.mkdir, .mkdir, .copy, .done])
        #expect(entries[0].destination.map { URL(filePath: $0).standardizedFileURL.path } == f.destination.standardizedFileURL.path)
        #expect(entries[1].destination.map { URL(filePath: $0).lastPathComponent } == "Food")
        try #require(plan.entries.count >= 1)
        #expect(entries[2].source == plan.entries[0].source.path)
        #expect(entries[2].destination == plan.entries[0].destination.path)
    }
}

struct JournalRepositoryTests {
    @Test func lastIsCompleteStates() throws {
        let tmp = try TempDir()
        let j = JournalRepository(directory: tmp.url.appending(path: "s", directoryHint: .isDirectory))
        #expect(try j.lastIsComplete() == nil)
        try j.append(JournalEntry(op: .copy, source: "/a", destination: "/b", time: .now))
        #expect(try j.lastIsComplete() == false)
        try j.append(JournalEntry(op: .done, source: nil, destination: nil, time: .now))
        #expect(try j.lastIsComplete() == true)
        #expect(try j.read().map(\.op) == [.copy, .done])
        try j.archive(suffix: "20261021-120000")
        #expect(try j.lastIsComplete() == nil)
        #expect(FileManager.default.fileExists(atPath: j.directory.appending(path: "journal.20261021-120000.jsonl").path))
    }

    @Test func archiveDoesNotOverwrite() throws {
        let tmp = try TempDir()
        let j = JournalRepository(directory: tmp.url)
        for _ in 0..<2 {
            try j.append(JournalEntry(op: .done, source: nil, destination: nil, time: .now))
            try j.archive(suffix: "same")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).filter { $0.hasPrefix("journal.") }
        #expect(names.count == 2)
    }

    @Test func truncatedLastLineIsIgnored() throws {
        let tmp = try TempDir()
        let j = JournalRepository(directory: tmp.url)
        try j.append(JournalEntry(op: .copy, source: "/a", destination: "/b", time: .now))
        let h = try FileHandle(forWritingTo: tmp.url.appending(path: "journal.jsonl"))
        try h.seekToEnd(); try h.write(contentsOf: Data("{\"op\":\"co".utf8)); try h.close()
        #expect(try j.read().map(\.op) == [.copy])
    }
}

struct LocalFileOpsTests {
    @Test func removeEmptyFolderKeepsFolderWithUserFile() throws {
        let tmp = try TempDir()
        let folder = tmp.url.appending(path: "Food", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mine = folder.appending(path: "mine.jpg")
        try Data([1]).write(to: mine)
        try Data([2]).write(to: folder.appending(path: ".DS_Store"))
        try LocalFileOps().removeEmptyFolder(folder)
        #expect(try Data(contentsOf: mine) == Data([1]))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: ".DS_Store").path))
    }

    @Test func removeEmptyFolderRemovesFolderWithOnlyDSStore() throws {
        let tmp = try TempDir()
        let folder = tmp.url.appending(path: "Food", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([2]).write(to: folder.appending(path: ".DS_Store"))
        try LocalFileOps().removeEmptyFolder(folder)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func removeEmptyFolderRemovesEmptyAndIgnoresMissing() throws {
        let tmp = try TempDir()
        let folder = tmp.url.appending(path: "Empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LocalFileOps().removeEmptyFolder(folder)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        try LocalFileOps().removeEmptyFolder(folder)  // Missing: no error.
    }

    @Test func removeEmptyFolderNeverRemovesSubfolders() throws {
        let tmp = try TempDir()
        let folder = tmp.url.appending(path: "Food", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
        try LocalFileOps().removeEmptyFolder(folder)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "sub").path))
    }
}
