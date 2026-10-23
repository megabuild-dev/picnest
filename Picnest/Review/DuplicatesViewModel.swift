import CoreGraphics
import Foundation
import Observation
import PicnestCore

/// State of the Duplicates view (spec 3.6). Talks to `ReviewService` only. Thumbnails come from
/// `thumbnail` (the `ThumbnailService` path of the Review screen), and trash errors go to `onTrashErrors`
/// (the Trash alert of the Review screen).
///
/// The view model keeps its own copy of the found groups with the Keep choices of the user. The shown
/// groups come from that copy and the current session: trashed photos leave their groups, and a group of
/// 1 photo is not shown. An undo puts the photos back in their groups. A rescan makes a new review, so
/// the next open finds the groups again.
///
/// A photo has 1 Keep state in both segments: a photo that is Keep in 1 group shows as Keep in every
/// group. The current Keep photo of an exact group is locked as Keep in its similar group (spec 14).
/// The card counts, the Clean Up All count, and the clean-up itself use this same set of Keep photos.
@MainActor
@Observable
final class DuplicatesViewModel {
    enum State: Equatable {
        case idle
        case finding(done: Int, total: Int)
        case ready
        /// Found, and no group is left.
        case empty
        case failed(String)
    }

    struct TileModel: Hashable {
        let name: String
        /// For example "4032 × 3024", or "" when the size is not known.
        let pixelSize: String
        /// For example "2.1 MB".
        let fileSize: String
    }

    static let notice = "Check each group. The app moves the photos that are not marked Keep to the Trash."
    static let emptyText = "No duplicates found."
    /// The width of a tile in a card, in points.
    static let tileWidth: Double = 200
    /// The decode size of a tile thumbnail.
    static let tileMaxPixel = ThumbnailService.maxPixel(forTileWidth: tileWidth)

    /// The segment that shows: **Exact copies** (default) or **Similar photos**.
    var kind: DuplicateGroup.Kind = .exact
    /// The photo that Quick Look shows, or nil when Quick Look is closed.
    var previewURL: URL?
    /// The last clicked tile. Space and Return open it in Quick Look.
    private(set) var anchor: MediaID?

    /// True while a clean-up runs. **Move <N> to Trash** and **Clean Up All** are off then.
    private(set) var isCleaning = false

    private var phase: State = .idle
    /// The found groups, with the Keep choices of the user. `ids` are as found. An exact group has its 1
    /// current Keep photo. A similar group has the photos that the user keeps, without exact Keep photos
    /// (those are locked as Keep while they are the Keep of their exact group).
    private var found: [DuplicateGroup] = []
    /// The indexes in `found` of the groups marked **Not Duplicates**. Their exact Keep photos stay protected.
    private var dismissed: Set<Int> = []

    @ObservationIgnored private let review: ReviewService
    @ObservationIgnored private let thumbnailLoader: (MediaID, Int) async -> CGImage?
    @ObservationIgnored private let onTrashErrors: ([TrashError]) -> Void
    @ObservationIgnored private var hasFound = false
    /// Every scanned photo. The scan does not change while this review is open.
    @ObservationIgnored private let mediaByID: [MediaID: MediaFile]
    @ObservationIgnored private let source: URL
    /// The cached shown groups, for the found groups and the trashed photos they were made for.
    @ObservationIgnored private var cache: (version: Int, trashed: Set<MediaID>, shown: Shown)?
    /// The highest `done` of the progress, so the bar never moves back.
    @ObservationIgnored private var lastDone = 0
    @ObservationIgnored private var version = 0
    /// How many times `find` searched. For tests.
    @ObservationIgnored private(set) var findCount = 0

    init(review: ReviewService, thumbnail: @escaping (MediaID, Int) async -> CGImage?,
         onTrashErrors: @escaping ([TrashError]) -> Void) {
        self.review = review
        thumbnailLoader = thumbnail
        self.onTrashErrors = onTrashErrors
        mediaByID = Dictionary(review.session.scan.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
    }

    // MARK: - Finding

    var state: State {
        phase == .ready && allGroups.isEmpty ? .empty : phase
    }

    /// Finds the groups on the first open of the view (spec 3.6). Later opens reuse the result. A
    /// cancelled search (the user left the view) runs again on the next open.
    func find() async {
        guard !hasFound, !isFinding else { return }
        phase = .finding(done: 0, total: 0)
        lastDone = 0
        findCount += 1
        do {
            let groups = try await review.findDuplicates { [weak self] done, total in
                Task { @MainActor in self?.progress(done, total) }
            }
            setFound(groups)
            hasFound = true
            phase = .ready
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("Picnest could not look for duplicates: \(error.localizedDescription)")
        }
    }

    private var isFinding: Bool {
        if case .finding = phase { return true }
        return false
    }

    /// Progress reports can come out of order: a lower `done` than the last one is ignored.
    func progress(_ done: Int, _ total: Int) {
        guard isFinding, done >= lastDone else { return }
        lastDone = done
        phase = .finding(done: done, total: total)
    }

    private func setFound(_ groups: [DuplicateGroup]) {
        let exactKeeps = Set(groups.filter { $0.kind == .exact }.flatMap(\.keepIDs))
        found = groups.map { g in
            var g = g
            if g.kind == .similar { g.keepIDs.subtract(exactKeeps) }
            return g
        }
        dismissed = []
        version += 1
    }

    // MARK: - Groups

    /// The shown groups and the Keep photos, made from `found` and the trashed photos.
    private struct Shown {
        /// `keepIDs` are the photos that show as Keep.
        var groups: [DuplicateGroup] = []
        /// The current Keep photo of every found exact group with a photo left, also of hidden groups.
        var exactKeeps: Set<MediaID> = []
        /// The photos that no clean-up trashes: `exactKeeps` and every shown Keep photo.
        var keeps: Set<MediaID> = []
    }

    private var shown: Shown {
        let trashed = review.session.trashedIDs
        if let cache, cache.version == version, cache.trashed == trashed { return cache.shown }
        let shown = makeShown(trashed: trashed)
        cache = (version, trashed, shown)
        return shown
    }

    /// The shown groups of both kinds. `keepIDs` are the photos that show as Keep.
    var allGroups: [DuplicateGroup] { shown.groups }

    /// The shown groups of `kind`.
    var groups: [DuplicateGroup] { allGroups.filter { $0.kind == kind } }

    var exactCount: Int { allGroups.count { $0.kind == .exact } }
    var similarCount: Int { allGroups.count { $0.kind == .similar } }

    func isKeep(_ id: MediaID, in g: DuplicateGroup) -> Bool { g.keepIDs.contains(id) }

    /// The count of **Move <N> to Trash**: the photos of the group that are not Keep (spec 3.6).
    func trashCount(of g: DuplicateGroup) -> Int { g.ids.count { !g.keepIDs.contains($0) } }

    func trashTitle(of g: DuplicateGroup) -> String { "Move \(trashCount(of: g)) to Trash" }

    /// The photos that **Clean Up All** moves to the Trash: the photos of the shown groups that are not
    /// Keep, each 1 time. It is also the count of the **Duplicates** sidebar item (0 until found).
    var cleanUpCount: Int {
        let s = shown
        return Set(s.groups.flatMap(\.ids)).subtracting(s.keeps).count
    }

    var cleanUpTitle: String { "Clean Up All (\(cleanUpCount))" }

    var cleanUpConfirmation: String {
        let n = cleanUpCount
        return "Move \(n) \(n == 1 ? "photo" : "photos") to the Trash? You can put them back with Undo or from the Trash in Finder."
    }

    // MARK: - Actions

    /// Marks or unmarks `id` as Keep (spec 3.6). An exact group has 1 Keep photo, so a click on another photo
    /// moves it. A similar group can keep more than 1. The last Keep photo, and the exact Keep photo in a
    /// similar group, cannot be unmarked.
    func toggleKeep(_ id: MediaID, in g: DuplicateGroup) {
        anchor = id
        let s = shown
        guard let index = index(of: g), let current = s.groups.first(where: { matches($0, g) }),
              current.ids.contains(id) else { return }
        let keeps: Set<MediaID>
        switch g.kind {
        case .exact:
            keeps = [id]
        case .similar:
            var shownKeeps = current.keepIDs
            if shownKeeps.contains(id) {
                guard shownKeeps.count > 1, !s.exactKeeps.contains(id) else { return }
                shownKeeps.remove(id)
            } else {
                shownKeeps.insert(id)
            }
            keeps = shownKeeps.subtracting(s.exactKeeps)
        }
        guard keeps != found[index].keepIDs else { return }
        found[index].keepIDs = keeps
        version += 1
    }

    /// **Move <N> to Trash**: moves the photos of the group that are not Keep to the Trash, as 1 undo step.
    func trash(_ g: DuplicateGroup) async {
        let s = shown
        guard let current = s.groups.first(where: { matches($0, g) }) else { return }
        await cleanUp([current], exactKeeps: s.exactKeeps)
    }

    /// **Clean Up All**, after the confirmation: every shown group, as 1 undo step.
    func cleanUpAll() async {
        let s = shown
        guard !s.groups.isEmpty else { return }
        await cleanUp(s.groups, exactKeeps: s.exactKeeps)
    }

    private func cleanUp(_ groups: [DuplicateGroup], exactKeeps: Set<MediaID>) async {
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false }
        onTrashErrors(await review.cleanUp(groups, exactKeeps: exactKeeps))
    }

    /// **Not Duplicates**: hides the group. The session stores its key, so a rescan that changes the group
    /// shows it again.
    func notDuplicates(_ g: DuplicateGroup) {
        guard let index = index(of: g), let current = allGroups.first(where: { matches($0, g) }) else { return }
        review.dismissDuplicates(current)
        dismissed.insert(index)
        version += 1
    }

    // MARK: - Tiles and Quick Look

    func tile(_ id: MediaID) -> TileModel {
        let media = mediaByID[id]
        let name = media.map { ($0.relativePath as NSString).lastPathComponent } ?? id
        let pixels = review.pixelSize(of: id).map { "\($0.width) × \($0.height)" } ?? ""
        let bytes = media.map { ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file) } ?? ""
        return TileModel(name: name, pixelSize: pixels, fileSize: bytes)
    }

    func thumbnail(_ id: MediaID, maxPixel: Int) async -> CGImage? {
        await thumbnailLoader(id, maxPixel)
    }

    /// Opens Quick Look for `id`, or for the last clicked tile.
    func openPreview(_ id: MediaID? = nil) {
        if let id { anchor = id }
        guard let anchor else { return }
        previewURL = url(of: anchor)
    }

    /// The photos that Quick Look can step through: the tiles of the shown segment, in order.
    var previewURLs: [URL] { groups.flatMap(\.ids).compactMap(url(of:)) }

    #if DEBUG
    /// Shows `groups` as found, with no search. For the Xcode preview.
    func showForPreview(_ groups: [DuplicateGroup]) {
        setFound(groups)
        hasFound = true
        phase = .ready
    }
    #endif

    // MARK: - Private

    /// The shown groups: trashed photos leave, a group with fewer than 2 photos left is not shown. A group
    /// with no Keep photo left keeps its best photo left. Then every photo that is Keep in 1 group (or is
    /// the current Keep of an exact group) shows as Keep in every group.
    private func makeShown(trashed: Set<MediaID>) -> Shown {
        var result = Shown()
        for g in found where g.kind == .exact {
            let present = g.ids.filter { !trashed.contains($0) }
            guard let best = present.first else { continue }
            let keeps = g.keepIDs.intersection(present)
            result.exactKeeps.formUnion(keeps.isEmpty ? [best] : keeps)
        }
        var base: [DuplicateGroup] = []
        for (i, g) in found.enumerated() where !dismissed.contains(i) {
            var g = g
            g.ids.removeAll { trashed.contains($0) }
            guard g.ids.count > 1 else { continue }
            g.keepIDs.formIntersection(g.ids)
            g.keepIDs.formUnion(g.ids.filter(result.exactKeeps.contains))
            if g.keepIDs.isEmpty { g.keepIDs = [g.ids[0]] }
            base.append(g)
        }
        result.keeps = base.reduce(into: result.exactKeeps) { $0.formUnion($1.keepIDs) }
        let keeps = result.keeps
        result.groups = base.map { g in
            var g = g
            g.keepIDs.formUnion(g.ids.filter(keeps.contains))
            return g
        }
        return result
    }

    /// The found group that `g` (a shown group) comes from. Groups of 1 kind have no photo in common.
    private func index(of g: DuplicateGroup) -> Int? {
        guard let first = g.ids.first else { return nil }
        return found.indices.first { found[$0].kind == g.kind && found[$0].ids.contains(first) && !dismissed.contains($0) }
    }
    private func matches(_ a: DuplicateGroup, _ b: DuplicateGroup) -> Bool {
        a.kind == b.kind && !Set(a.ids).isDisjoint(with: b.ids)
    }

    private func url(of id: MediaID) -> URL? {
        mediaByID[id].map { source.appending(path: $0.relativePath) }
    }
}
