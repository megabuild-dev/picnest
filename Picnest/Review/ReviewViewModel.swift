import CoreGraphics
import Foundation
import Observation
import PicnestCore
import SwiftUI

/// State of the Review screen (spec 3.3). Talks to `ReviewService`, `ClassifyService`, `ThumbnailService`
/// and `LibraryService` (for **Undo Last Sort**) only, and asks `AppModel` (through `onRescan`) to scan again.
@MainActor
@Observable
final class ReviewViewModel {
    enum SidebarItem: Hashable {
        case all, notSure, changedByYou, category(CategoryID), duplicates, dontMove, videos, unreadable
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case lowestConfidence, date, name

        var id: Self { self }

        var title: String {
            switch self {
            case .lowestConfidence: "Lowest confidence"
            case .date: "Date"
            case .name: "Name"
            }
        }
    }

    /// The badge at the top left of a tile. Tiles without a score (Don't move, videos, unreadable) have none.
    enum Badge: Hashable {
        /// Green if not uncertain, amber if uncertain.
        case percent(Int, isUncertain: Bool)
        /// A manual pick: "✓ You".
        case you
    }

    /// The Not sure photos with the same best guess (spec 3.4).
    struct NotSureGroup: Hashable, Identifiable {
        let category: CategoryID
        let categoryName: String
        /// In `sortOrder`.
        let ids: [MediaID]

        var id: CategoryID { category }
    }

    struct TileModel: Hashable {
        let name: String
        let secondLine: String
        let badge: Badge?
    }

    static let columnRange = 2...8
    static let noDate = "no date"
    /// The emoji of a category that the user makes with **New Category…**.
    static let newCategoryEmoji = "📁"

    var selectedItem: SidebarItem = .all {
        didSet { if selectedItem != oldValue { clearSelection() } }
    }
    var sortOrder: SortOrder = .lowestConfidence
    /// Grid columns, 2...8. The toolbar slider sets it.
    var columns = 3 {
        didSet {
            let clamped = min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
            if clamped != columns { columns = clamped }
        }
    }
    /// The selected photos. Only visible photos stay selected.
    private(set) var selection: Set<MediaID> = []
    /// The last photo that a plain click or a ⌘-click selected. ⇧-click selects the range from here,
    /// and Quick Look opens this photo.
    private(set) var anchor: MediaID?
    /// True while the New Category alert shows. The alert sets it to false before it runs a button
    /// action, so the move intent is kept apart in `pendingMoveIDs`.
    var isNamingNewCategory = false
    /// The photo that Quick Look shows, or nil when Quick Look is closed.
    var previewURL: URL?
    /// The text of the Trash alert (a photo that could not move to the Trash or come back), or nil.
    var trashMessage: String?
    /// The title of the Trash alert: the action that failed (**Move to Trash**, **Undo**, or **Redo**).
    private(set) var trashAlertTitle = "Move to Trash"
    /// The Duplicates view (spec 3.6). Made with this review, so a rescan finds the groups again.
    @ObservationIgnored private(set) var duplicates: DuplicatesViewModel!

    @ObservationIgnored private let review: ReviewService
    @ObservationIgnored private let classify: ClassifyService
    @ObservationIgnored private let thumbnails: ThumbnailService
    @ObservationIgnored private let onRescan: () -> Void
    @ObservationIgnored private let library: LibraryService
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let source: URL
    /// True until `suggestAfterScanIfNeeded` runs once for a review that a scan opened (spec 3.7).
    @ObservationIgnored private var suggestAfterScanPending: Bool
    /// Open a photo in its default app, and show photos in Finder. `NSWorkspace` by default; tests replace them.
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let revealURLs: @MainActor ([URL]) -> Void
    /// A lookup of every scanned photo, trashed ones too: a photo that comes back from the Trash needs its
    /// entry. Lists use `session.visibleMedia`. The scan does not change while this review is open: a rescan
    /// makes a new `ReviewService`.
    /// The latest task that waits for an undo or redo of the Trash and then shows its errors.
    @ObservationIgnored private var undoWatch: Task<Void, Never>?
    @ObservationIgnored private let mediaByID: [MediaID: MediaFile]

    /// The cached `visibleIDs`, for the item and order they were made for. Selection changes re-render the
    /// grid, so the list must not be filtered and sorted again then (spec 12, risk 3).
    @ObservationIgnored private var cache: (item: SidebarItem, order: SortOrder, ids: [MediaID])?
    /// Set when `review.session` changes; the next read of `visibleIDs` makes the list again.
    @ObservationIgnored private var sessionChanged = false
    /// The cached `notSureGroups`, for the order they were made for. Dropped with `cache` when the session changes.
    @ObservationIgnored private var groupsCache: (order: SortOrder, groups: [NotSureGroup])?
    /// How many times the Not sure groups were made. For tests.
    @ObservationIgnored private(set) var groupComputations = 0
    /// How many times the list was filtered and sorted. For tests.
    @ObservationIgnored private(set) var listComputations = 0
    /// The photos that the next new category gets: the selection when **Move to…** opened the alert.
    /// Only `createNewCategory` and `cancelNewCategory` clear it.
    private var pendingMoveIDs: [MediaID]?

    private static let dayFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

    /// `app` holds the undo flag that every window shares, and starts over (`startOver`). `afterScan` is true
    /// when a scan or a rescan opened this review.
    init(review: ReviewService, classify: ClassifyService, thumbnails: ThumbnailService, library: LibraryService,
         app: AppModel, afterScan: Bool = false, onRescan: @escaping () -> Void,
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         revealURLs: @escaping @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }) {
        self.openURL = openURL
        self.revealURLs = revealURLs
        self.review = review
        self.classify = classify
        self.thumbnails = thumbnails
        self.library = library
        self.app = app
        self.onRescan = onRescan
        suggestAfterScanPending = afterScan
        source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
        mediaByID = Dictionary(review.session.scan.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let media = mediaByID, source = source
        duplicates = DuplicatesViewModel(
            review: review,
            thumbnail: { id, maxPixel in
                guard let file = media[id] else { return nil }
                return await thumbnails.thumbnail(for: file, source: source, maxPixel: maxPixel)
            },
            onTrashErrors: { [weak self] in self?.showTrashErrors($0) })
        watchSession()
    }

    // MARK: - Sidebar

    /// The categories in sidebar order.
    var categories: [PicnestCore.Category] {
        review.session.categories.sorted { $0.order < $1.order }
    }

    /// The count of every sidebar item, from 1 call of `ReviewService.counts()`.
    var sidebarCounts: [SidebarItem: Int] {
        let counts = review.counts()
        var result: [SidebarItem: Int] = [
            .all: counts.all, .notSure: counts.notSure, .changedByYou: counts.changedByYou,
            .dontMove: counts.dontMove, .videos: counts.videos, .unreadable: counts.unreadable,
            .duplicates: duplicates.cleanUpCount,
        ]
        for category in review.session.categories {
            result[.category(category.id)] = counts.perCategory[category.id] ?? 0
        }
        return result
    }

    func count(of item: SidebarItem) -> Int { sidebarCounts[item] ?? 0 }

    // MARK: - Toolbar

    var title: String {
        switch selectedItem {
        case .all: "All photos"
        case .notSure: "Not sure"
        case .changedByYou: "Changed by you"
        case .category(let c):
            review.session.categories.first { $0.id == c }.map { "\($0.emoji) \($0.displayName)" } ?? "Category"
        case .duplicates: "Duplicates"
        case .dontMove: "Don't move"
        case .videos: "Videos"
        case .unreadable: "Unreadable"
        }
    }

    var count: Int { count(of: selectedItem) }

    /// The source folder path with the home folder as `~`.
    var sourcePathText: String { Self.abbreviate(review.session.sourcePath, home: NSHomeDirectory()) }

    nonisolated static func abbreviate(_ path: String, home: String) -> String {
        let home = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    func rescan() {
        guard canSortOrRescan else { return }
        onRescan()
    }

    // MARK: - After a sort (spec 2, step 9)

    /// True after a sort, until **Done** closes the session: the toolbar shows **Undo Last Sort**.
    var canUndoLastSort: Bool { review.session.sortedAt != nil }
    /// True while **Undo Last Sort** runs in any window.
    var isUndoingSort: Bool { app.isUndoingSort }
    /// False while a sort or an undo of a sort runs, while files move to or from the Trash (final review I1),
    /// or while **Start Over…** runs: **Rescan**, **Sort Photos…**, **Undo Last Sort**, and **Start Over…** are off.
    var canSortOrRescan: Bool {
        !isUndoingSort && !review.isMovingFiles && !app.isStartingOver && !library.isSortRunning
    }
    /// The text of the Undo Last Sort alert, or nil.
    var undoSortMessage: String?
    /// The text of the save alert, or nil after a good save (final review I4).
    var saveErrorMessage: String? { review.saveError.map(SortMessages.saveFailed) }

    /// **Try Again** in the save alert.
    func retrySave() { review.retrySave() }

    /// **OK** in the save alert. The next failed save shows the alert again.
    func dismissSaveError() { review.dismissSaveError() }

    /// Reverses the last sort and clears the sort time, so the review is unsorted again.
    func undoLastSort() async {
        guard canUndoLastSort, canSortOrRescan, app.beginUndo() else { return }
        defer { app.endUndo() }
        do {
            try await library.undoLastSort(review: review)
        } catch {
            undoSortMessage = SortMessages.text(for: error)
        }
    }

    // MARK: - Done (organize in place, spec 7.2)

    /// True while **Done** moves the classified photos into category folders in the source folder.
    var isOrganizing: Bool { app.isOrganizing }
    /// The files done and total of the running organize, or nil.
    var organizeProgress: (done: Int, total: Int)? { app.organizeProgress }
    /// The text of a failed organize, or nil.
    var organizeErrorMessage: String? { app.organizeErrorMessage }

    /// **Done** is on when there is at least 1 category and no sort, undo, or Trash move runs.
    var canDone: Bool { !review.session.categories.isEmpty && canSortOrRescan && !app.isOrganizing }

    /// **Done**: move every classified photo into a category sub-folder of the source folder, rename it,
    /// and close the session (spec 7.2). One-way.
    func done() {
        guard canDone else { return }
        app.organizeAndFinish()
    }

    /// **OK** in the organize error alert.
    func dismissOrganizeError() { app.organizeErrorMessage = nil }

    // MARK: - Start Over… (spec 3.3)

    /// **Start Over…** is off when **Rescan** is off: while a sort, an undo of a sort, or a Trash move runs.
    var canStartOver: Bool { canSortOrRescan }
    /// True while the Start Over confirmation shows.
    var isConfirmingStartOver = false
    /// The text of the Start Over error alert (the last sort did not finish), or nil.
    var startOverErrorMessage: String?

    /// The text of the Start Over confirmation.
    var startOverMessage: String {
        let text = "The app scans the folder again and proposes new categories. Your categories and picks are lost."
        return canUndoLastSort ? text + " The last sort can no longer be undone." : text
    }

    /// File > **Start Over…**: shows the confirmation.
    func requestStartOver() {
        guard canStartOver else { return }
        isConfirmingStartOver = true
    }

    /// **Start Over** in the confirmation. On an error the review stays and the alert shows its text.
    func startOver() async {
        guard canStartOver else { return }
        do {
            try await app.startOver()
        } catch {
            startOverErrorMessage = SortMessages.text(for: error)
        }
    }

    // MARK: - Grid

    /// The photos of `selectedItem` in `sortOrder`. Made again only when the item, the order, or the
    /// session changes.
    var visibleIDs: [MediaID] {
        let item = selectedItem, order = sortOrder
        let session = review.session  // Also makes the reading view depend on the session.
        refreshIfSessionChanged()
        if let cache, cache.item == item, cache.order == order { return cache.ids }
        let ids: [MediaID]
        if item == .notSure {
            // The grouped view shows the photos group by group, so grid order is the flattened groups.
            ids = notSureGroups.flatMap(\.ids)
        } else {
            let files = session.visibleMedia.filter { Self.includes($0, state: session.states[$0.id], in: item) }
            ids = sorted(files, session: session)
        }
        cache = (item, order, ids)
        listComputations += 1
        dropHiddenSelection(visible: ids)
        return ids
    }

    /// The grid columns for `columns`.
    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: ReviewStyle.gridSpacing), count: columns)
    }

    // MARK: - Not sure

    /// The open Suggest Categories sheet, or nil.
    var suggest: SuggestViewModel?

    /// **Suggest Categories…** shows in the Not sure view when it has at least 7 photos (spec 3.4).
    var canSuggest: Bool { count(of: .notSure) >= SuggestionService.minimumPhotos }

    /// Shows the Not sure view and opens the suggest sheet.
    func openSuggest() {
        selectedItem = .notSure
        let thumbnails = thumbnails, media = mediaByID, source = source
        suggest = SuggestViewModel(
            review: review,
            thumbnail: { id, maxPixel in
                guard let file = media[id] else { return nil }
                return await thumbnails.thumbnail(for: file, source: source, maxPixel: maxPixel)
            },
            onAdded: { [weak self] _ in self?.suggest = nil })
    }

    func closeSuggest() { suggest = nil }

    /// Opens the suggest sheet when a scan opened this review and many images are Not sure (spec 3.7).
    /// Runs once per review: a closed sheet does not open again until the next scan.
    func suggestAfterScanIfNeeded() {
        guard suggestAfterScanPending else { return }
        suggestAfterScanPending = false
        if review.hasManyNotSure { openSuggest() }
    }

    /// The Not sure photos by best guess, largest group first. Photos follow `sortOrder`. Made again
    /// only when the order or the session changes.
    var notSureGroups: [NotSureGroup] {
        let order = sortOrder
        let session = review.session
        refreshIfSessionChanged()
        if let groupsCache, groupsCache.order == order { return groupsCache.groups }
        let files = session.visibleMedia.filter { Self.includes($0, state: session.states[$0.id], in: .notSure) }
        let position = Dictionary(
            sorted(files, session: session).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(session.categories.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let groups = review.notSureGroups.map { group in
            NotSureGroup(category: group.category, categoryName: names[group.category] ?? "Unknown",
                         ids: group.ids.sorted { (position[$0] ?? .max) < (position[$1] ?? .max) })
        }
        groupsCache = (order, groups)
        groupComputations += 1
        return groups
    }

    /// **Accept N** of the group at `index`: its photos go to the best guess and become "Changed by you".
    func acceptGroup(at index: Int) {
        let groups = notSureGroups
        guard groups.indices.contains(index) else { return }
        review.acceptGroup(bestCategory: groups[index].category)
        dropHiddenSelection(visible: visibleIDs)
    }

    /// **Select All** of the group at `index`: replaces the selection with the group.
    func selectGroup(at index: Int) {
        let groups = notSureGroups
        guard groups.indices.contains(index), let first = groups[index].ids.first else { return }
        selection = Set(groups[index].ids)
        anchor = first
    }

    /// **Accept All Best Guesses**.
    func acceptAll() {
        review.acceptAllNotSure()
        clearSelection()
    }

    func tile(_ id: MediaID) -> TileModel {
        let session = review.session
        let state = session.states[id]
        let name = mediaByID[id].map { Self.fileName($0) } ?? id
        let badge: Badge? = switch state {
        case .manual: .you
        case .auto(let a): .percent(a.percent, isUncertain: a.uncertain)
        case .heldNotSure(let a): .percent(a.percent, isUncertain: true)
        case .dontMove, .unreadable, nil: nil
        }
        return TileModel(name: name, secondLine: secondLine(id, state: state, session: session), badge: badge)
    }

    /// The decode size for a tile of `width` points, or 0 while the tile has no width yet. The tile
    /// keys its load task on this value, so the task runs again when the width becomes known.
    func loadPixels(forTileWidth width: Double) -> Int {
        width > 0 ? ThumbnailService.maxPixel(forTileWidth: width) : 0
    }

    func thumbnail(_ id: MediaID, maxPixel: Int) async -> CGImage? {
        guard let media = mediaByID[id] else { return nil }
        return await thumbnails.thumbnail(for: media, source: source, maxPixel: maxPixel)
    }

    // MARK: - Selection and Quick Look

    /// Plain click: only `id`. ⌘-click: adds or removes `id`. ⇧-click: adds the photos from the anchor
    /// to `id` in grid order. Plain click and ⌘-click move the anchor to `id`.
    func click(_ id: MediaID, modifiers: EventModifiers) {
        if modifiers.contains(.shift), let anchor, let range = range(from: anchor, to: id) {
            selection.formUnion(range)
        } else if modifiers.contains(.command) {
            if selection.remove(id) == nil {
                selection.insert(id)
                anchor = id
            } else if anchor == id {
                anchor = nil
            }
        } else {
            selection = [id]
            anchor = id
        }
    }

    /// Right-click on `id`: selects only `id` unless it is already selected.
    func contextMenuSelect(_ id: MediaID) {
        guard !selection.contains(id) else { return }
        selection = [id]
        anchor = id
    }

    /// The photos that a context menu on `id` acts on: the selection in grid order if `id` is selected,
    /// else `id`. Pure: it does not change the selection.
    func contextTargets(for id: MediaID) -> [MediaID] { dragIDs(for: id) }

    /// True if at least 1 of `ids` is in "Not sure". Pure.
    func canAccept(_ ids: [MediaID]) -> Bool {
        let states = review.session.states
        return ids.contains { states[$0]?.isNotSure == true }
    }

    /// Opens `id`, or the anchor photo, in its default app.
    func openInDefaultApp(_ id: MediaID? = nil) {
        guard let target = id ?? anchor, let media = mediaByID[target] else { return }
        openURL(url(of: media))
    }

    /// Shows the selected photos in Finder.
    func showInFinder() {
        let urls = selectedInGridOrder.compactMap { mediaByID[$0].map(url(of:)) }
        guard !urls.isEmpty else { return }
        revealURLs(urls)
    }

    func selectAll() { selection = Set(visibleIDs) }

    func clearSelection() {
        selection = []
        anchor = nil
    }

    /// The photos that a drag of `id` carries: the selection in grid order if `id` is selected, else `id`.
    func dragIDs(for id: MediaID) -> [MediaID] {
        selection.contains(id) ? selectedInGridOrder : [id]
    }

    /// Opens Quick Look for `id` (selecting it unless it is already selected), or for the anchor photo.
    func openPreview(_ id: MediaID? = nil) {
        if let id {
            if !selection.contains(id) { selection = [id] }
            anchor = id
        }
        guard let anchor, let media = mediaByID[anchor] else { return }
        previewURL = url(of: media)
    }

    /// The photos that Quick Look can step through: the visible photos in grid order.
    var previewURLs: [URL] { visibleIDs.compactMap { mediaByID[$0].map(url(of:)) } }

    // MARK: - Photo actions

    /// True if at least 1 selected photo is in "Not sure", so **Accept Best Guess** has work to do.
    var canAcceptSelection: Bool {
        let states = review.session.states
        return selection.contains { states[$0]?.isNotSure == true }
    }

    func moveSelection(to c: CategoryID) {
        review.move(selectedInGridOrder, to: c)
        clearSelection()
    }

    /// Keys 1 to 9: moves the selection to the category at place `n` of the sidebar (its `order` is
    /// `n - 1`). Returns false, and does nothing, without a selection or such a category.
    @discardableResult
    func moveSelection(toKey n: Int) -> Bool {
        let categories = categories
        guard !selection.isEmpty, (1...9).contains(n), n <= categories.count else { return false }
        moveSelection(to: categories[n - 1].id)
        return true
    }

    func acceptSelection() {
        review.acceptBestGuess(selectedInGridOrder)
        clearSelection()
    }

    func dontMoveSelection() {
        review.dontMove(selectedInGridOrder)
        clearSelection()
    }

    /// Photos dropped on a sidebar category. Returns false for an empty drop.
    @discardableResult
    func drop(_ ids: [MediaID], on c: CategoryID) -> Bool {
        guard !ids.isEmpty else { return false }
        review.move(ids, to: c)
        clearSelection()
        return true
    }

    var canUndo: Bool { review.canUndo }
    var canRedo: Bool { review.canRedo }
    /// A ⌘Z or ⇧⌘Z that does nothing shows no Trash alert (final review M1).
    func undo() {
        let runs = review.canUndo
        review.undo()
        if runs { watchTrashErrors(title: "Undo") }
    }

    func redo() {
        let runs = review.canRedo
        review.redo()
        if runs { watchTrashErrors(title: "Redo") }
    }

    /// Moves the selected photos to the Trash, with no confirmation (spec 3.3). They leave every list; **Undo**
    /// puts them back. A photo that cannot move stays, and `trashMessage` tells why.
    func trashSelection() async {
        let ids = selectedInGridOrder
        guard !ids.isEmpty else { return }
        let errors = await review.moveToTrash(ids)
        clearSelection()
        showTrashErrors(errors)
    }

    /// Waits for the background work of the latest undo or redo, and for its message. For tests.
    func settled() async { await undoWatch?.value }

    /// A Trash undo or redo runs in the background: wait for it, then show what failed.
    private func watchTrashErrors(title: String) {
        let review = review
        undoWatch = Task { [weak self] in
            await review.settled()
            self?.showTrashErrors(review.lastUndoErrors, title: title)
        }
    }

    /// The Trash alert: the first message, and "and <n> more" for the other errors. Also for the
    /// clean-ups of the Duplicates view.
    func showTrashErrors(_ errors: [TrashError], title: String = "Move to Trash") {
        guard let first = errors.first else { return }
        trashAlertTitle = title
        let more = errors.count - 1
        trashMessage = more > 0 ? "\(first.message) (and \(more) more)" : first.message
    }

    // MARK: - Category edits

    var canDeleteCategory: Bool { review.canDeleteCategory }

    /// The text of the confirmation dialog before a delete (spec 3.3).
    func deleteConfirmation(for c: CategoryID) -> String {
        let name = review.session.categories.first { $0.id == c }?.displayName ?? ""
        return "Delete \(name)? Its \(count(of: .category(c))) photos go to Not sure."
    }

    /// Deletes `c`. Its photos go to "Not sure", so that list shows if `c` was showing.
    func deleteCategory(_ c: CategoryID) {
        guard canDeleteCategory else { return }
        review.delete(c)
        if selectedItem == .category(c) { selectedItem = .notSure }
    }

    /// The categories that `c` can merge into, in sidebar order.
    func mergeTargets(for c: CategoryID) -> [PicnestCore.Category] {
        categories.filter { $0.id != c }
    }

    func merge(_ c: CategoryID, into target: CategoryID) {
        review.merge(c, into: target)
        if selectedItem == .category(c) { selectedItem = .category(target) }
    }

    /// Renames `c`. A name that is empty after trimming is ignored.
    func renameCategory(_ c: CategoryID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        review.rename(c, to: name)
    }

    /// Sets the icon of `c`. Returns false, and does nothing, unless `emoji` is exactly 1 emoji.
    @discardableResult
    func setEmoji(_ c: CategoryID, _ emoji: String) -> Bool {
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSingleEmoji(emoji) else { return false }
        review.setEmoji(c, emoji)
        return true
    }

    /// True if `text` is exactly 1 character and that character shows as an emoji. A plain symbol
    /// such as "1" or "☺" without the emoji variation selector is not an emoji here.
    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first, let first = character.unicodeScalars.first else {
            return false
        }
        let properties = first.properties
        return properties.isEmojiPresentation || (properties.isEmoji && character.unicodeScalars.count > 1)
    }

    /// The sidebar drag of category rows (`List.onMove` offsets, in sidebar order).
    func moveCategories(from offsets: IndexSet, to destination: Int) {
        var ids = categories.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        review.reorder(ids)
    }

    /// Shows the New Category alert. From **Move to…**, the new category gets the photos that are
    /// selected now.
    func requestNewCategory(movingSelection: Bool) {
        pendingMoveIDs = movingSelection && !selection.isEmpty ? selectedInGridOrder : nil
        isNamingNewCategory = true
    }

    /// True if the open New Category request moves photos into the new category.
    var newCategoryMovesPhotos: Bool { pendingMoveIDs != nil }

    /// The Create button of the alert. The alert always closes. A name that is empty after trimming
    /// makes nothing and returns false. Names can repeat.
    @discardableResult
    func createNewCategory(name: String) -> Bool {
        let moving = pendingMoveIDs
        pendingMoveIDs = nil
        isNamingNewCategory = false
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let id = review.addCategory(name: name, emoji: Self.newCategoryEmoji)
        if let moving, !moving.isEmpty {
            review.move(moving, to: id)
            clearSelection()
        }
        return true
    }

    /// The Cancel button of the alert.
    func cancelNewCategory() {
        pendingMoveIDs = nil
        isNamingNewCategory = false
    }

    // MARK: - Private

    /// Drops both caches once after `review.session` changed, and watches the session again.
    private func refreshIfSessionChanged() {
        guard sessionChanged else { return }
        sessionChanged = false
        watchSession()
        cache = nil
        groupsCache = nil
    }

    /// Marks the list as old at the next change of `review.session`. The tracking fires 1 time, so
    /// `visibleIDs` calls this again when it makes the list.
    private func watchSession() {
        withObservationTracking {
            _ = review.session
        } onChange: { [weak self] in
            // ReviewService is @MainActor, so its changes (and this callback) happen on the main actor.
            MainActor.assumeIsolated { self?.sessionChanged = true }
        }
    }

    /// The selected photos in grid order. Selected photos that are not visible come last, by id.
    private var selectedInGridOrder: [MediaID] {
        let visible = visibleIDs.filter { selection.contains($0) }
        let rest = selection.subtracting(visible).sorted()
        return visible + rest
    }

    /// The contiguous slice of the grid between `a` and `b`, or nil if 1 of them is not visible.
    private func range(from a: MediaID, to b: MediaID) -> ArraySlice<MediaID>? {
        let ids = visibleIDs
        guard let i = ids.firstIndex(of: a), let j = ids.firstIndex(of: b) else { return nil }
        return ids[min(i, j)...max(i, j)]
    }

    /// Unselects photos that left the list. Writes only on a change, so a read does not re-render.
    private func dropHiddenSelection(visible ids: [MediaID]) {
        guard !selection.isEmpty || anchor != nil else { return }
        let visible = Set(ids)
        let kept = selection.intersection(visible)
        if kept != selection { selection = kept }
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
    }

    private func url(of media: MediaFile) -> URL { source.appending(path: media.relativePath) }

    private static func fileName(_ media: MediaFile) -> String {
        (media.relativePath as NSString).lastPathComponent
    }

    private static func includes(_ media: MediaFile, state: PhotoState?, in item: SidebarItem) -> Bool {
        switch item {
        case .all: return true
        case .notSure: return state?.isNotSure == true
        case .changedByYou: return state?.isManual == true
        case .category(let c):
            // Same rule as `ReviewService.counts().perCategory`: manual picks and certain auto photos.
            switch state {
            case .manual(c): return true
            case .auto(let a): return a.categoryID == c && !a.uncertain
            default: return false
            }
        case .duplicates: return false  // The Duplicates view shows groups, not the grid.
        case .dontMove: return state == .dontMove
        case .videos: return media.kind == .video
        case .unreadable: return state == .unreadable
        }
    }

    /// Lowest confidence: scored photos by percent, then manual picks, then photos without a score.
    /// Date: oldest first; photos without a date use their modification time. Ties go by name.
    private func sorted(_ files: [MediaFile], session: Session) -> [MediaID] {
        struct Key {
            let id: MediaID
            let name: String
            let rank: Int
            let percent: Int
            let date: Date
        }
        let keys = files.map { media -> Key in
            let state = session.states[media.id]
            let (rank, percent): (Int, Int) = switch state {
            case .auto(let a), .heldNotSure(let a): (0, a.percent)
            case .manual: (1, 0)
            default: (2, 0)
            }
            return Key(id: media.id, name: Self.fileName(media), rank: rank, percent: percent,
                       date: session.scan.dates[media.id]?.date ?? media.modified)
        }
        func byName(_ l: Key, _ r: Key) -> Bool {
            let result = l.name.localizedStandardCompare(r.name)
            return result == .orderedSame ? l.id < r.id : result == .orderedAscending
        }
        let order: (Key, Key) -> Bool = switch sortOrder {
        case .lowestConfidence: { l, r in
            if l.rank != r.rank { return l.rank < r.rank }
            if l.percent != r.percent { return l.percent < r.percent }
            return byName(l, r)
        }
        case .date: { l, r in l.date != r.date ? l.date < r.date : byName(l, r) }
        case .name: byName
        }
        return keys.sorted(by: order).map(\.id)
    }

    /// "or <name> <n>%" in Not sure if there is a second guess; else the date, or "no date" when only
    /// the modification time is known (spec 3.3).
    private func secondLine(_ id: MediaID, state: PhotoState?, session: Session) -> String {
        if selectedItem == .notSure, let a = Self.assignment(state), let second = a.secondCategoryID,
           let category = session.categories.first(where: { $0.id == second }),
           let percent = classify.secondPercent(of: a) {
            return "or \(category.displayName) \(percent)%"
        }
        guard let date = session.scan.dates[id], date.source != .modificationTime else { return Self.noDate }
        return date.date.formatted(Self.dayFormat)
    }

    private static func assignment(_ state: PhotoState?) -> Assignment? {
        switch state {
        case .auto(let a), .heldNotSure(let a): a
        default: nil
        }
    }
}
