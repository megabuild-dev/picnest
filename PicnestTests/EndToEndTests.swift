import CryptoKit
import Foundation
import PicnestCore
import Testing
@testable import Picnest

/// Embedder for the end-to-end test. Photos `a…` and `b…` point at the first prompt of the first and the
/// second All topics candidate. Photos `c…` sit between them, so they are "Not sure". Other prompts point away.
private struct GroupEmbedder: Embedder {
    let dimension = 4
    let first: String
    let second: String

    init() throws {
        let candidates = try CandidateRepository().load(.all)
        first = candidates[0].prompts[0]
        second = candidates[1].prompts[0]
    }

    func embedImages(_ urls: [URL]) async throws -> [Vector] {
        urls.map { url in
            switch url.lastPathComponent.first {
            case "a": [1, 0, 0, 0]
            case "b": [0, 1, 0, 0]
            default: [1, 1, 0, 0]
            }
        }
    }

    func embedTexts(_ texts: [String]) async throws -> [Vector] {
        texts.map { $0 == first ? [1, 0, 0, 0] : $0 == second ? [0, 1, 0, 0] : [0, 0, 1, 0] }
    }
}

/// The full flow of spec 2 and 9.1 through the view models, with 30 generated photos (Task 19, Step 6
/// stand-in): scan, review changes, quit and reopen, Copy + Undo Last Sort, Move with date folders + Undo.
@MainActor
@Suite(.serialized)
struct EndToEndTests {
    private let temp: TempDir
    private let suite = TestDefaults()
    private let embedder: GroupEmbedder
    private static let locale = Locale(identifier: "en_US")

    init() throws {
        temp = try TempDir()
        embedder = try GroupEmbedder()
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(embedder: embedder, sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
    }

    /// 30 photos with different bytes: 12 `a`, 10 `b`, 8 `c`.
    private func makePhotos(in folder: URL) throws {
        let names = (0..<12).map { "a\($0)" } + (0..<10).map { "b\($0)" } + (0..<8).map { "c\($0)" }
        for (i, name) in names.enumerated() {
            let bytes = (0..<(200 + i * 7)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ i) }
            try Data(bytes).write(to: folder.appending(path: "\(name).jpg"))
        }
    }

    /// Every file and folder under `root`, as a relative path and the SHA-256 of its bytes ("dir" for folders).
    private func snapshot(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let base = root.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let walker = FileManager.default.enumerator(
            at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isDirectoryKey]) else { return [:] }
        for case let url as URL in walker {
            let path = String(url.resolvingSymlinksInPath().path(percentEncoded: false).dropFirst(base.count))
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                result[path] = "dir"
            } else {
                result[path] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            }
        }
        return result
    }

    private func review(_ app: AppModel) throws -> ReviewService {
        guard case .review(let review, _) = app.screen else { throw Failure.notInReview("\(app.screen)") }
        return review
    }

    private enum Failure: Error { case notInReview(String) }

    private func sortModel(_ env: AppEnvironment, _ app: AppModel) async throws -> SortViewModel {
        let model = SortViewModel(review: try review(app), sortService: env.sortService, library: env.library,
                                  locale: Self.locale, onDone: app.done)
        await model.load()
        return model
    }

    @Test func fullFlowWithCopyAndMoveIsUndone() async throws {
        let work = try temp.folder("Work")
        let source = try temp.folder("Work/Photos")
        try makePhotos(in: source)
        let before = try snapshot(work)
        #expect(before.values.filter { $0 != "dir" }.count == 30)

        // 1. Open the folder and scan it.
        var env: AppEnvironment? = makeEnvironment()
        var app: AppModel? = AppModel(environment: env!)
        var welcome: WelcomeViewModel? = WelcomeViewModel(app: app!, library: env!.library, locale: Self.locale)
        welcome!.choose(source)
        await app!.settled()
        let scan = ScanViewModel(app: app!, scanService: env!.scanService, source: source, openURL: { _ in })
        scan.start()
        await scan.settled()
        await app!.settled()
        var reviewModel: ReviewViewModel? = ReviewViewModel(
            review: try review(app!), classify: env!.classifyService, thumbnails: env!.thumbnails,
            library: env!.library, app: app!, onRescan: {})
        let categories = reviewModel!.categories
        try #require(categories.count >= 2)
        #expect(reviewModel!.count(of: .all) == 30)

        // 2. Rename a category, move 5 photos, accept a Not sure group.
        let renamed = categories[0].id, target = categories[1].id
        reviewModel!.renameCategory(renamed, to: "Kids' art")
        reviewModel!.selectedItem = .category(renamed)
        let moved = Array(reviewModel!.visibleIDs.filter { $0.hasPrefix("a") }.prefix(5))
        #expect(moved.count == 5)
        for id in moved { reviewModel!.click(id, modifiers: .command) }
        reviewModel!.moveSelection(to: target)
        reviewModel!.selectedItem = .notSure
        let group = try #require(reviewModel!.notSureGroups.first)
        reviewModel!.acceptGroup(at: 0)
        await try review(app!).settled()

        // 3. Quit (drop every model and service) and open the folder again: the changes are still there.
        reviewModel = nil
        welcome = nil
        app = nil
        env = nil
        let env2 = makeEnvironment()
        let app2 = AppModel(environment: env2)
        let welcome2 = WelcomeViewModel(app: app2, library: env2.library, locale: Self.locale)
        #expect(welcome2.recent.map(\.photoCount) == [30])
        welcome2.openRecent(try #require(welcome2.recent.first))
        await app2.settled()
        let reopened = try review(app2).session
        #expect(reopened.categories.first { $0.id == renamed }?.displayName == "Kids' art")
        for id in moved { #expect(reopened.states[id] == .manual(target)) }
        for id in group.ids { #expect(reopened.states[id] == .manual(group.category)) }

        // 4. Sort with Copy, Done, then Undo Last Sort from the recent list.
        let copy = try await sortModel(env2, app2)
        copy.sort()
        await copy.finished()
        guard case .finished(let copied, 0) = copy.state else { Issue.record("copy: \(copy.state)"); return }
        #expect(copied > 0)
        #expect(try snapshot(work) != before)
        copy.done()
        await app2.settled()
        guard case .welcome = app2.screen else { Issue.record("expected welcome"); return }
        welcome2.refresh()
        let sorted = try #require(welcome2.recent.first)
        #expect(welcome2.sortedText(sorted) != nil)
        #expect(welcome2.canUndoLastSort(sorted))
        await welcome2.undoLastSort(sorted)
        #expect(welcome2.undoMessage == nil)
        #expect(try snapshot(work) == before)

        // 5. Open again (no question: the sort was undone), sort with Move and date folders, then undo.
        welcome2.openRecent(try #require(welcome2.recent.first))
        #expect(welcome2.newSortRequest == nil)
        await app2.settled()
        let move = try await sortModel(env2, app2)
        move.options.mode = .move
        move.options.dateFolders = true
        await move.planned()
        move.sort()
        #expect(move.state == .confirmingMove)
        move.confirmMove()
        await move.finished()
        guard case .finished(0, let movedCount) = move.state else { Issue.record("move: \(move.state)"); return }
        #expect(movedCount > 0)
        #expect(try snapshot(work) != before)
        move.done()
        await app2.settled()
        welcome2.refresh()
        let movedEntry = try #require(welcome2.recent.first)
        #expect(welcome2.canUndoLastSort(movedEntry))
        await welcome2.undoLastSort(movedEntry)
        #expect(welcome2.undoMessage == nil)
        #expect(try snapshot(work) == before)
    }
}
