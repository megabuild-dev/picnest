import CoreGraphics
import Foundation
import Observation
import PicnestCore
import SwiftUI

/// The 3 filters of the toolbar. Each one is a sidebar item (`ReviewViewModel.filter`).
enum PhotoFilter: CaseIterable {
    case all, needsReview, chosenByYou
}

/// What makes a Needs Review photo hard to categorize. The 3 filter menus of the Needs Review view.
enum ReviewIssue: CaseIterable {
    case lowConfidence, noCategory, similarPhotos
}

/// Where the Add Photos sheet puts the photos.
enum AddPhotosTarget: Identifiable, Hashable {
    case category(CategoryID)
    case collection(CollectionID)

    var id: Self { self }
}

/// What the collection sheet does.
enum CollectionEditor: Identifiable, Equatable {
    case new(name: String, adding: [MediaID])
    case rename(CollectionID)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let c): c.uuidString
        }
    }
}

/// State of the Review screen (spec 3.3). Talks to `ReviewService`, `ClassifyService`, `ThumbnailService`
/// and `LibraryService` (for **Undo Last Sort**) only, and asks `AppModel` (through `onRescan`) to scan again.
/// Where a layout takes its photos from.
enum LayoutOrigin: Hashable {
    case selection, category(CategoryID), collection(CollectionID)
}

@MainActor
@Observable
final class ReviewViewModel {
    enum SidebarItem: Hashable {
        case all, notSure, changedByYou, category(CategoryID), duplicates, dontMove, videos, unreadable
        case favorites, collection(CollectionID), recentlyDeleted
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case lowestConfidence, date, name

        var id: Self { self }

        var title: String {
            switch self {
            case .lowestConfidence: String(localized: "Lowest confidence")
            case .date: String(localized: "Date")
            case .name: String(localized: "Name")
            }
        }
    }

    /// The badge of a tile. Tiles without a score (Don't move, videos, unreadable) have none.
    /// The tile shows an uncertain score on the photo and "Chosen by you" below the photo.
    enum Badge: Hashable {
        case percent(Int, isUncertain: Bool)
        /// A manual pick.
        case you
    }

    /// The Needs Review photos with the same best guess (spec 3.4).
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
        /// The VoiceOver label: file name, category, and state.
        let accessibilityLabel: String
    }

    static let noDate = String(localized: "no date")
    /// The emoji of a category that the user makes with **New Category…**.
    static let newCategoryEmoji = "📁"

    var selectedItem: SidebarItem = .all {
        didSet {
            guard selectedItem != oldValue, !isRevertingItem else { return }
            if let activeEditor {
                // The open editor holds this item. Keep it until the editor closes (it may ask first).
                let requested = selectedItem
                isRevertingItem = true
                selectedItem = oldValue
                isRevertingItem = false
                itemAfterClose = requested
                activeEditor.session.requestClose()
                return
            }
            // The issue filter belongs to the Needs Review view only.
            reviewIssue = nil
            clearSelection()
        }
    }
    var sortOrder: SortOrder = .lowestConfidence
    /// The issue filter of Needs Review, or nil for all Needs Review photos. It combines with the search text.
    /// Choosing similar photos starts the duplicate search if it has not run yet.
    var reviewIssue: ReviewIssue? {
        didSet {
            guard reviewIssue != oldValue else { return }
            startOrCancelSimilarSearch(leaving: oldValue == .similarPhotos)
            dropSelectionHiddenByFilter()
        }
    }
    /// The search that the similar-photos filter started, or nil. Another issue, another sidebar item, or the end
    /// of the model cancels it; a cancelled search is idle again (`DuplicatesViewModel.find`).
    @ObservationIgnored nonisolated(unsafe) private(set) var similarSearch: Task<Void, Never>?

    private func startOrCancelSimilarSearch(leaving: Bool) {
        similarSearch?.cancel()
        similarSearch = nil
        // Leaving the filter frees the search at once, so the Duplicates view or the filter can start it again.
        if leaving { duplicates?.cancelFind() }
        guard reviewIssue == .similarPhotos else { return }
        guard let duplicates else { return }
        similarSearch = Task { await duplicates.find() }
    }

    deinit { similarSearch?.cancel() }

    /// True after the user closes the amber notice of Needs Review. A rescan makes a new view model, so it shows again.
    var isNoticeDismissed = false


    /// The toolbar filter. It reads and writes `selectedItem`; a category reads as `.all`.
    var filter: PhotoFilter {
        get {
            switch selectedItem {
            case .notSure: .needsReview
            case .changedByYou: .chosenByYou
            default: .all
            }
        }
        set {
            selectedItem = switch newValue {
            case .all: .all
            case .needsReview: .notSure
            case .chosenByYou: .changedByYou
            }
        }
    }

    /// Shows only the photos whose file name contains this text, ignoring case and diacritics.
    /// Empty or blank text shows all. Sidebar counts do not change.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            cache = nil
            dropSelectionHiddenByFilter()
        }
    }

    static let thumbnailSizeRange: ClosedRange<Double> = 80...240
    static let defaultThumbnailSize = 160.0
    private static let thumbnailSizeKey = "thumbnailSize"

    /// The grid thumbnail size in points, 80...240. Saved in `UserDefaults` key `thumbnailSize`.
    var thumbnailSize: Double {
        didSet {
            let clamped = Self.clampedThumbnailSize(thumbnailSize)
            if clamped != thumbnailSize { thumbnailSize = clamped; return }
            defaults.set(clamped, forKey: Self.thumbnailSizeKey)
        }
    }
    @ObservationIgnored private let defaults: UserDefaults

    private static func clampedThumbnailSize(_ value: Double) -> Double {
        min(max(value, thumbnailSizeRange.lowerBound), thumbnailSizeRange.upperBound)
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
    private(set) var trashAlertTitle = String(localized: "Move to Trash")
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
    @ObservationIgnored private let photoEdits: PhotoEditService
    @ObservationIgnored private let layoutExport: LayoutExportService
    @ObservationIgnored private let chooseExportDestination: @MainActor (String, URL, ExportFormat) async -> (URL, ExportFormat)?
    @ObservationIgnored private let chooseLayoutDestination: @MainActor (String, URL, LayoutExportFormat) async -> (URL, LayoutExportFormat)?
    /// The editor that fills the window, or nil. It opens with `openEditor` and closes with `closeEditor`.
    private(set) var activeEditor: ActiveEditor? {
        didSet { app.editorChanged(from: oldValue?.session, to: activeEditor?.session) }
    }
    /// The photo editor, or nil when none or another editor is open.
    var editor: PhotoEditorViewModel? {
        if case .photo(let editor)? = activeEditor { editor } else { nil }
    }
    /// The sidebar item that the user chose while the editor was open. It shows when the editor closes.
    @ObservationIgnored private var itemAfterClose: SidebarItem?
    @ObservationIgnored private var isRevertingItem = false
    @ObservationIgnored private let folderExists: (URL) -> Bool
    /// A lookup of every scanned photo, trashed ones too: a photo that comes back from the Trash needs its
    /// entry. Lists use `session.visibleMedia`. The scan does not change while this review is open: a rescan
    /// makes a new `ReviewService`.
    /// The latest task that waits for an undo or redo of the Trash and then shows its errors.
    @ObservationIgnored private var undoWatch: Task<Void, Never>?
    /// A lookup of every scanned photo, trashed ones too: a photo that comes back from the Trash needs its
    /// entry. Lists use `session.visibleMedia`. It changes only when a folder rename gives photos new paths.
    private var mediaByID: [MediaID: MediaFile] { review.mediaByID }
    @ObservationIgnored private var seenMediaRevision: Int

    /// The cached `visibleIDs`, for the item and order they were made for. Selection changes re-render the
    /// grid, so the list must not be filtered and sorted again then (spec 12, risk 3).
    @ObservationIgnored private var cache: (item: SidebarItem, order: SortOrder, filter: GroupFilter, ids: [MediaID])?
    /// Set when `review.session` changes; the next read of `visibleIDs` makes the list again.
    @ObservationIgnored private var sessionChanged = false
    /// The cached `notSureGroups`, for the order they were made for. Dropped with `cache` when the session changes.
    @ObservationIgnored private var groupsCache: (order: SortOrder, filter: GroupFilter, groups: [NotSureGroup])?
    /// How many times the Needs Review groups were made. For tests.
    @ObservationIgnored private(set) var groupComputations = 0
    /// How many times the list was filtered and sorted. For tests.
    @ObservationIgnored private(set) var listComputations = 0
    /// The photos that the next new category gets: the selection when **Move to…** opened the alert.
    /// Only `createNewCategory` and `cancelNewCategory` clear it.
    private var pendingMoveIDs: [MediaID]?

    /// `app` holds the undo flag that every window shares, and starts over (`startOver`). `afterScan` is true
    /// when a scan or a rescan opened this review.
    init(review: ReviewService, classify: ClassifyService, thumbnails: ThumbnailService, library: LibraryService,
         photoEdits: PhotoEditService, layoutExport: LayoutExportService, app: AppModel, afterScan: Bool = false, onRescan: @escaping () -> Void,
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         revealURLs: @escaping @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) },
         folderExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
         defaults: UserDefaults = .standard, duplicateSearch: DuplicatesViewModel.Search? = nil,
         chooseExportDestination: (@MainActor (_ suggestedName: String, _ folder: URL, _ format: ExportFormat) async -> (URL, ExportFormat)?)? = nil,
         chooseLayoutDestination: (@MainActor (_ suggestedName: String, _ folder: URL, _ format: LayoutExportFormat) async -> (URL, LayoutExportFormat)?)? = nil) {
        self.defaults = defaults
        self.photoEdits = photoEdits
        self.layoutExport = layoutExport
        self.chooseExportDestination = chooseExportDestination ?? { name, folder, format in
            await EditorSavePanel.choose(
                suggestedName: name, folder: folder, format: format, title: EditorSavePanel.title(of:))
        }
        self.chooseLayoutDestination = chooseLayoutDestination ?? { name, folder, format in
            await EditorSavePanel.choose(
                suggestedName: name, folder: folder, format: format, title: EditorSavePanel.title(of:))
        }
        let saved = defaults.object(forKey: Self.thumbnailSizeKey) as? Double
        thumbnailSize = Self.clampedThumbnailSize(saved ?? Self.defaultThumbnailSize)
        self.folderExists = folderExists
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
        seenMediaRevision = review.mediaRevision
        let source = source
        duplicates = DuplicatesViewModel(
            review: review,
            thumbnail: { [review] id, maxPixel in
                guard let file = await review.mediaByID[id] else { return nil }
                return await thumbnails.thumbnail(for: file, source: source, maxPixel: maxPixel)
            },
            onTrashErrors: { [weak self] in self?.showTrashErrors($0) },
            search: duplicateSearch)
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
            .favorites: CollectionService.visibleFavorites(in: review.session).count,
            .recentlyDeleted: review.session.trashed.count,
        ]
        for category in review.session.categories {
            result[.category(category.id)] = counts.perCategory[category.id] ?? 0
        }
        for collection in review.session.collections {
            result[.collection(collection.id)] = CollectionService.visibleMembers(of: collection.id, in: review.session).count
        }
        return result
    }

    func count(of item: SidebarItem) -> Int { sidebarCounts[item] ?? 0 }

    // MARK: - Toolbar

    var title: String {
        switch selectedItem {
        case .all: String(localized: "All Photos")
        case .notSure: String(localized: "Needs Review")
        case .changedByYou: String(localized: "Chosen by you")
        case .category(let c):
            review.session.categories.first { $0.id == c }.map { "\($0.emoji) \($0.displayName)" }
                ?? String(localized: "Category")
        case .duplicates: String(localized: "Duplicates")
        case .dontMove: String(localized: "Don't move")
        case .videos: String(localized: "Videos")
        case .unreadable: String(localized: "Unreadable")
        case .favorites: String(localized: "Favorites")
        case .collection(let c): collections.first { $0.id == c }?.name ?? String(localized: "Collection")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        }
    }

    var count: Int { count(of: selectedItem) }

    /// A path with the home folder as `~`.
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
    /// or while **Start Over…** runs, or while the photo editor is open: **Rescan**, **Sort Photos…**,
    /// **Undo Last Sort**, **Done**, and **Start Over…** are off.
    var canSortOrRescan: Bool {
        !isEditing && !isUndoingSort && !review.isMovingFiles && !app.isStartingOver && !library.isSortRunning
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
        canUndoLastSort
            ? String(localized: "The app scans the folder again and proposes new categories. Your categories and picks are lost. Your favorites and collections are lost too. The last sort can no longer be undone.")
            : String(localized: "The app scans the folder again and proposes new categories. Your categories and picks are lost. Your favorites and collections are lost too.")
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
        let filter = groupFilter
        if let cache, cache.item == item, cache.order == order, cache.filter == filter { return cache.ids }
        var ids: [MediaID]
        if item == .notSure {
            // The grouped view shows the photos group by group, so grid order is the flattened groups.
            ids = notSureGroups.flatMap(\.ids)
        } else if item == .recentlyDeleted {
            ids = recentlyDeletedIDs(session: session, search: filter.search)
        } else {
            let needle = SearchText.needle(filter.search)
            let members = Self.members(of: item, in: session)
            let files = session.visibleMedia.filter { media in
                Self.includes(media, state: session.states[media.id], in: item, members: members)
                    && (needle.map { Self.matches(media, needle: $0) } ?? true)
            }
            ids = sorted(files, session: session)
        }
        cache = (item, order, filter, ids)
        listComputations += 1
        dropHiddenSelection(visible: ids)
        return ids
    }

    /// The grid columns: as many as fit, each at least `thumbnailSize` wide.
    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize), spacing: Theme.Metrics.gridSpacing)]
    }

    /// What the grid shows instead of tiles when it has none.
    enum EmptyState: Equatable {
        /// The search text matches no photo. The action is **Clear Search**.
        case noResults
        /// The folder has no photos. The action is **Rescan**.
        case emptyFolder
        /// The Needs Review chip has no photo. No action.
        case nothingToReview
        /// The similar-photos filter waits for the duplicate search.
        case findingSimilar
        /// The duplicate search failed. The text is the error of the Duplicates view.
        case similarSearchFailed(String)
        /// The Chosen by you chip has no photo. No action.
        case noneChosen
        /// Favorites has no photo. No action.
        case noFavorites
        /// The collection has no visible photo. No action here; the header has **Add Photos**.
        case emptyCollection
        /// Recently Deleted has no photo. No action.
        case nothingDeleted
    }

    /// The empty state of the flat grid, or nil when it has photos. The Needs Review and Duplicates views
    /// have their own empty views, and a list with no search text keeps the plain "No Photos" message
    /// unless the whole folder is empty.
    var emptyState: EmptyState? {
        guard selectedItem != .duplicates, visibleIDs.isEmpty else { return nil }
        if selectedItem == .notSure {
            // Nothing left to check, or a search or issue filter that hides the photos that are left.
            if count(of: .notSure) == 0 { return .nothingToReview }
            if reviewIssue == .similarPhotos { return Self.similarEmptyState(for: duplicates.state) }
            return .noResults
        }
        if SearchText.needle(searchText) != nil { return .noResults }
        switch selectedItem {
        case .favorites: return .noFavorites
        case .collection: return .emptyCollection
        case .recentlyDeleted: return .nothingDeleted
        default: break
        }
        if count(of: .all) == 0 { return .emptyFolder }
        return selectedItem == .changedByYou ? .noneChosen : nil
    }

    /// What the similar-photos filter shows when no photo shows: a wait while the duplicate search has not
    /// finished, its error if it failed, else "no results".
    static func similarEmptyState(for phase: DuplicatesViewModel.State) -> EmptyState {
        switch phase {
        case .idle, .finding: .findingSimilar
        case .failed(let message): .similarSearchFailed(message)
        case .ready, .empty: .noResults
        }
    }

    // MARK: - Library chrome

    /// Which body the detail column shows.
    enum BodyKind: Equatable {
        case duplicates, needsReview, library, recentlyDeleted
    }

    var bodyKind: BodyKind {
        switch selectedItem {
        case .duplicates: .duplicates
        case .notSure: .needsReview
        case .recentlyDeleted: .recentlyDeleted
        default: .library
        }
    }

    /// The category that `selectedItem` shows, or nil for any other item.
    var selectedCategory: PicnestCore.Category? {
        guard case .category(let id) = selectedItem else { return nil }
        return categories.first { $0.id == id }
    }

    /// The header shows at the top of the library body of a category and of a collection.
    var showsCategoryHeader: Bool { selectedCategory != nil || selectedCollection != nil }

    /// The filter chips show for All Photos and Chosen by you. Needs Review has its own header and filter menus.
    var showsFilterChips: Bool {
        switch selectedItem {
        case .all, .changedByYou: true
        default: false
        }
    }

    /// The grid or list switch shows for the flat views only.
    var showsLayoutPicker: Bool { bodyKind == .library || bodyKind == .recentlyDeleted }

    /// The "N photos" footer shows under the flat views only.
    var showsFooter: Bool { bodyKind == .library || bodyKind == .recentlyDeleted }

    /// The thumbnail size slider. Needs Review is always a grid; the list has no thumbnail size.
    func showsThumbnailSlider(layout: LibraryLayout) -> Bool {
        switch bodyKind {
        case .duplicates: false
        case .needsReview: true
        case .library, .recentlyDeleted: layout == .grid
        }
    }

    // MARK: - Needs Review

    /// The open Suggest Categories sheet, or nil.
    var suggest: SuggestViewModel?

    /// **Suggest Categories…** shows in the Needs Review view when it has at least 7 photos (spec 3.4).
    var canSuggest: Bool { count(of: .notSure) >= SuggestionService.minimumPhotos }

    /// Shows the Needs Review view and opens the suggest sheet.
    func openSuggest() {
        selectedItem = .notSure
        let thumbnails = thumbnails, review = review, source = source
        suggest = SuggestViewModel(
            review: review,
            thumbnail: { id, maxPixel in
                guard let file = await review.mediaByID[id] else { return nil }
                return await thumbnails.thumbnail(for: file, source: source, maxPixel: maxPixel)
            },
            onAdded: { [weak self] _ in self?.suggest = nil })
    }

    func closeSuggest() { suggest = nil }

    /// Opens the suggest sheet when a scan opened this review and many images are Needs Review (spec 3.7).
    /// Runs once per review: a closed sheet does not open again until the next scan.
    func suggestAfterScanIfNeeded() {
        guard suggestAfterScanPending else { return }
        suggestAfterScanPending = false
        if review.hasManyNotSure { openSuggest() }
    }

    /// What narrows the Needs Review photos: the search text and the issue filter. For the similar issue it
    /// holds the photos of the found similar groups, so the caches see a finished duplicate search.
    private struct GroupFilter: Equatable {
        var search: String
        var issue: ReviewIssue?
        var similar: Set<MediaID>
    }

    private var groupFilter: GroupFilter {
        GroupFilter(search: searchText, issue: reviewIssue,
                    similar: reviewIssue == .similarPhotos ? similarPhotoIDs : [])
    }

    /// The photos of the found similar-photo groups. Empty until the duplicate search has run.
    private var similarPhotoIDs: Set<MediaID> {
        Set(duplicates.allGroups.filter { $0.kind == .similar }.flatMap(\.ids))
    }

    /// True if the Needs Review photo `id` has the `issue`. Pure over the state and the found similar photos.
    private func hasIssue(_ issue: ReviewIssue, id: MediaID, state: PhotoState?, filter: GroupFilter) -> Bool {
        let assignment = Self.assignment(state)
        switch issue {
        // The weak-score branch of the uncertain rule, with the settings of the classifier.
        case .lowConfidence: return assignment?.isWeakMatch(settings: classify.settings) ?? false
        // No score at all: the placeholder guess of a photo without an image vector.
        case .noCategory: return assignment?.isPlaceholder ?? true
        case .similarPhotos: return filter.similar.contains(id)
        }
    }

    /// The Needs Review photos by best guess, largest group first, narrowed by the search text and the issue
    /// filter. Photos follow `sortOrder`. Groups with no matching photo are left out. Made again only when
    /// the order, the filter, or the session changes.
    var notSureGroups: [NotSureGroup] {
        let order = sortOrder
        let session = review.session
        refreshIfSessionChanged()
        let filter = groupFilter
        if let groupsCache, groupsCache.order == order, groupsCache.filter == filter { return groupsCache.groups }
        let needle = SearchText.needle(filter.search)
        let files = session.visibleMedia.filter { media in
            let state = session.states[media.id]
            guard Self.includes(media, state: state, in: .notSure) else { return false }
            if let needle, !Self.matches(media, needle: needle) { return false }
            if let issue = filter.issue,
               !hasIssue(issue, id: media.id, state: state, filter: filter) { return false }
            return true
        }
        let position = Dictionary(
            sorted(files, session: session).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(session.categories.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let groups = review.notSureGroups.enumerated().compactMap { index, group -> (Int, NotSureGroup)? in
            let ids = group.ids.filter { position[$0] != nil }.sorted { (position[$0] ?? .max) < (position[$1] ?? .max) }
            guard !ids.isEmpty else { return nil }
            return (index, NotSureGroup(category: group.category,
                                        categoryName: names[group.category] ?? String(localized: "Unknown"), ids: ids))
        }
        // Largest group first, by the photos that show; ties keep the order of the review service.
        let sortedGroups = groups.sorted { l, r in
            l.1.ids.count != r.1.ids.count ? l.1.ids.count > r.1.ids.count : l.0 < r.0
        }.map(\.1)
        groupsCache = (order, filter, sortedGroups)
        groupComputations += 1
        return sortedGroups
    }

    /// The photos of the rendered `group` that still show in its category group: visible and still Needs Review.
    /// The order of the groups can change between the render and the click, so the group is found again by its
    /// category and never by its position.
    private func shownIDs(of group: NotSureGroup) -> [MediaID] {
        guard let current = notSureGroups.first(where: { $0.category == group.category }) else { return [] }
        let rendered = Set(group.ids)
        return current.ids.filter(rendered.contains)
    }

    /// **Accept N** of the rendered `group`: its photos that still show go to the best guess and become
    /// "Changed by you". Hidden photos (search, issue filter) stay in Needs Review.
    func acceptGroup(_ group: NotSureGroup) {
        let ids = shownIDs(of: group)
        guard !ids.isEmpty else { return }
        review.acceptBestGuess(ids)
        dropHiddenSelection(visible: visibleIDs)
    }

    /// **Select All** of the rendered `group`: replaces the selection with its photos that still show.
    func selectGroup(_ group: NotSureGroup) {
        let ids = shownIDs(of: group)
        guard let first = ids.first else { return }
        selection = Set(ids)
        anchor = first
    }

    /// **Accept All Best Guesses**: the shown photos only.
    func acceptAll() {
        review.acceptBestGuess(notSureGroups.flatMap(\.ids))
        clearSelection()
    }

    /// How many Needs Review photos have `issue`, ignoring the search text. For similar photos it counts the
    /// found similar groups, so it is 0 until the duplicate search has run.
    func reviewIssueCount(_ issue: ReviewIssue) -> Int {
        let session = review.session
        refreshIfSessionChanged()
        let filter = GroupFilter(search: "", issue: issue, similar: issue == .similarPhotos ? similarPhotoIDs : [])
        return session.visibleMedia.count { media in
            let state = session.states[media.id]
            return Self.includes(media, state: state, in: .notSure)
                && hasIssue(issue, id: media.id, state: state, filter: filter)
        }
    }

    /// Whether the menu of `issue` shows. A menu with no match is hidden, except the chosen one. The similar
    /// menu shows until the duplicate search has run, because choosing it starts the search.
    func isReviewIssueAvailable(_ issue: ReviewIssue) -> Bool {
        if reviewIssue == issue { return true }
        if issue == .similarPhotos {
            switch duplicates.state {
            case .ready, .empty: break
            default: return true
            }
        }
        return reviewIssueCount(issue) > 0
    }

    /// Clears the search text and the issue filter.
    func clearReviewFilters() {
        searchText = ""
        reviewIssue = nil
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
        return TileModel(
            name: name, secondLine: secondLine(id, state: state, session: session), badge: badge,
            accessibilityLabel: accessibilityLabel(id, name: name, state: state, session: session))
    }

    /// What a row of the list layout shows for `id`. The category text is the emoji and name, "Needs Review", or "—".
    struct ListRowModel: Equatable {
        let name: String
        let categoryText: String
        /// Nil when only the modification time is known.
        let date: Date?
        let fileSize: Int64
        let accessibilityLabel: String
    }

    func listRow(_ id: MediaID) -> ListRowModel {
        let tile = tile(id)
        let facts = inspectorFacts(for: id)
        let categoryText: String = switch facts?.status ?? InspectorFacts.Status.none {
        case .category(let emoji, let name): "\(emoji) \(name)"
        case .notSure: String(localized: "Needs Review")
        case .staysHere: String(localized: "Don't move")
        case .none: "—"
        }
        return ListRowModel(
            name: tile.name, categoryText: categoryText, date: facts?.date, fileSize: facts?.fileSize ?? 0,
            accessibilityLabel: tile.accessibilityLabel)
    }

    private func accessibilityLabel(_ id: MediaID, name: String, state: PhotoState?, session: Session) -> String {
        var parts = [name]
        let categoryID: CategoryID? = switch state {
        case .manual(let c): c
        case .auto(let a) where !a.uncertain: a.categoryID
        default: nil
        }
        if let categoryID, let category = session.categories.first(where: { $0.id == categoryID }) {
            parts.append(category.displayName)
        }
        if state?.isNotSure == true {
            parts.append(String(localized: "Needs Review"))
            if let a = Self.assignment(state) { parts.append("\(a.percent)%") }
        }
        if state?.isManual == true { parts.append(String(localized: "Chosen by you")) }
        if isFavorite(id) { parts.append(String(localized: "Favorite")) }
        if selection.contains(id) { parts.append(String(localized: "selected")) }
        return parts.joined(separator: ", ")
    }

    /// What the inspector shows. A photo selection comes first, then the category of the screen, else a hint.
    var inspectorContent: InspectorContent {
        if selection.count > 1 { return .many(selection.count) }
        if let id = selection.first, let facts = inspectorFacts(for: id) { return .photo(facts) }
        if let category = selectedCategory {
            return .category(CategoryFacts(
                id: category.id, emoji: category.emoji, name: category.displayName,
                photoCount: count(of: .category(category.id)), folderName: categoryFolderName(category.id),
                canReveal: categoryFolder(category.id) != nil))
        }
        return .hint
    }

    /// The facts of the inspector for `id`, or nil if the photo is unknown.
    func inspectorFacts(for id: MediaID) -> InspectorFacts? {
        guard let media = mediaByID[id] else { return nil }
        let session = review.session
        let state = session.states[id]
        func name(_ c: CategoryID) -> String? { session.categories.first { $0.id == c }?.displayName }
        let assignment = Self.assignment(state)
        let status: InspectorFacts.Status
        switch state {
        case .manual(let c):
            let category = session.categories.first { $0.id == c }
            status = category.map { .category(emoji: $0.emoji, name: $0.displayName) } ?? .none
        case .dontMove: status = .staysHere
        case .unreadable, nil: status = .none
        case .auto, .heldNotSure:
            if state?.isNotSure == true { status = .notSure }
            else if let a = assignment, let category = session.categories.first(where: { $0.id == a.categoryID }) {
                status = .category(emoji: category.emoji, name: category.displayName)
            } else { status = .none }
        }
        var suggestion: InspectorFacts.Suggestion?
        if state?.isNotSure == true, let a = assignment, let best = name(a.categoryID) {
            suggestion = InspectorFacts.Suggestion(
                categoryName: best, alternativeName: a.secondCategoryID.flatMap(name),
                alternativePercent: classify.secondPercent(of: a))
        }
        let date = session.scan.dates[id].flatMap { $0.source == .modificationTime ? nil : $0.date }
        return InspectorFacts(
            id: id, name: Self.fileName(media), status: status, date: date, fileSize: media.size,
            confidence: assignment?.percent, isChosenByYou: state?.isManual == true, suggestion: suggestion,
            isUncertain: state?.isNotSure == true)
    }

    /// The pixel size of `id`, read off the main thread. Nil if the file cannot be read.
    func pixelSize(of id: MediaID) async -> PixelSize? {
        guard let media = mediaByID[id] else { return nil }
        return await thumbnails.pixelSize(of: media, source: source)
    }

    /// The decode size for a tile of `width` points, or 0 while the tile has no width yet. The tile
    /// keys its load task on this value, so the task runs again when the width becomes known.
    func loadPixels(forTileWidth width: Double) -> Int {
        width > 0 ? ThumbnailService.maxPixel(forTileWidth: width) : 0
    }

    func thumbnail(_ id: MediaID, maxPixel: Int) async -> CGImage? {
        // A trashed photo is no longer under the source folder: read it from the Trash.
        if let record = review.session.trashed.first(where: { $0.mediaID == id }) {
            return await thumbnails.thumbnail(at: URL(filePath: record.trashPath), maxPixel: maxPixel)
        }
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

    /// True if at least 1 of `ids` is in "Needs Review". Pure.
    func canAccept(_ ids: [MediaID]) -> Bool {
        let states = review.session.states
        return ids.contains { states[$0]?.isNotSure == true }
    }

    /// Opens `id`, or the anchor photo, in its default app.
    func openInDefaultApp(_ id: MediaID? = nil) {
        guard let target = id ?? anchor, let media = mediaByID[target] else { return }
        openURL(url(of: media))
    }

    /// The file URLs of the selected photos, in grid order.
    func selectedURLs() -> [URL] {
        selectedInGridOrder.compactMap { mediaByID[$0].map(url(of:)) }
    }

    /// Shows the selected photos in Finder.
    func showInFinder() {
        reveal(selectedURLs())
    }

    /// The folder that Done made for category `c` (`<source>/<category folder>`), or nil if it is not on disk yet.
    func categoryFolder(_ c: CategoryID) -> URL? {
        guard let name = SortPlanner.folderNames(for: review.session.categories)[c] else { return nil }
        let folder = source.appending(path: name, directoryHint: .isDirectory)
        return folderExists(folder) ? folder : nil
    }

    /// Opens the folder of category `c` in Finder, without selecting any photo. Does nothing if the folder
    /// is not on disk yet.
    func showCategoryInFinder(_ c: CategoryID) {
        guard let folder = categoryFolder(c) else { return }
        openURL(folder)
    }

    /// Reveals `urls` in 1 Finder window. Finder opens 1 window per parent folder, so it keeps only
    /// the files in the folder of the first URL.
    private func reveal(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let folder = first.deletingLastPathComponent()
        revealURLs(urls.filter { $0.deletingLastPathComponent() == folder })
    }

    func selectAll() { selection = Set(visibleIDs) }

    /// The first 3 selected photos in grid order: the thumbnails of the selection bar.
    var selectionPreviewIDs: [MediaID] {
        Array(visibleIDs.lazy.filter { self.selection.contains($0) }.prefix(3))
    }

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
        guard bodyKind != .recentlyDeleted, let anchor, let media = mediaByID[anchor] else { return }
        previewURL = url(of: media)
    }

    /// The photos that Quick Look can step through: the visible photos in grid order.
    var previewURLs: [URL] { visibleIDs.compactMap { mediaByID[$0].map(url(of:)) } }

    // MARK: - Photo editor (UI redesign, Phase 4)

    var isEditing: Bool { activeEditor != nil }

    /// True if the photo editor can open `id`: a readable image that is not in the Trash, outside Recently
    /// Deleted, while no files move and no editor is open.
    func canEdit(_ id: MediaID) -> Bool {
        canSortOrRescan && bodyKind != .recentlyDeleted && isEditable(id)
    }

    /// True for a readable image that is not in the Trash. Ignores the state of the screen.
    private func isEditable(_ id: MediaID) -> Bool {
        guard let media = mediaByID[id], media.kind == .image else { return false }
        return review.session.states[id] != .unreadable && !review.session.trashed.contains { $0.mediaID == id }
    }

    /// Opens the photo editor. The set is the selected images in grid order when 2 or more photos are selected,
    /// else the visible images of the current item. It starts at `id`, or at the anchor photo.
    func openEditor(_ id: MediaID? = nil) {
        guard let start = id ?? anchor, canEdit(start) else { return }
        let ids = selection.count >= 2 ? selectedInGridOrder : visibleIDs
        let photos = ids.filter(isEditable).compactMap { id in
            mediaByID[id].map { EditorPhoto(id: id, url: url(of: $0), fileName: Self.fileName($0)) }
        }
        guard !photos.isEmpty else { return }
        itemAfterClose = nil
        activeEditor = .photo(PhotoEditorViewModel(
            photos: photos, start: start, service: photoEdits, protected: protectedFilesProvider,
            chooseDestination: chooseExportDestination,
            revealURL: { [weak self] in self?.revealURLs([$0]) },
            onClose: { [weak self] in self?.closeEditor() },
            onCancelClose: { [weak self] in self?.itemAfterClose = nil },
            readSize: { [weak self] id in await self?.pixelSize(of: id) }))
    }

    /// The files that no export may replace: every photo of the folder and every file in the Trash. The editor
    /// calls this after the save panel returns, so a photo that moved or went to the Trash meanwhile counts.
    /// It reads the live review, not a copy made when the editor opened (final review C1).
    private var protectedFilesProvider: @MainActor () -> ProtectedFiles {
        { [review, source] in
            ProtectedFiles(
                source: source, mediaIDs: Set(review.mediaByID.values.map(\.relativePath)),
                otherPaths: review.session.trashed.map(\.trashPath))
        }
    }

    /// Closes the editor and drops its edit. The selection stays. A sidebar item that the user chose
    /// meanwhile shows now.
    func closeEditor() {
        // An export still needs the editor, its lock, and its place to show an error (final review C1, I2).
        guard activeEditor?.session.isExporting != true else { return }
        activeEditor = nil
        if let item = itemAfterClose {
            itemAfterClose = nil
            selectedItem = item
        }
    }

    // MARK: - Layout editor (UI redesign, Phase 5)

    /// The layout editor, or nil when none or another editor is open.
    var layoutEditor: LayoutEditorViewModel? {
        if case .layout(let editor)? = activeEditor { editor } else { nil }
    }

    /// The origin that the user has not yet decided on: set when a draft with photos exists.
    var askingToContinueLayout: LayoutOrigin?

    /// True if a layout can start from `origin`: no files move and no editor is open, and the origin has at
    /// least 1 readable image that is not in the Trash.
    func canCreateLayout(from origin: LayoutOrigin) -> Bool {
        canSortOrRescan && !layoutPhotoIDs(of: origin).isEmpty
    }

    /// The same for a right-click on `id`: the selection if `id` is selected, else `id`.
    func canCreateLayout(for id: MediaID) -> Bool {
        canSortOrRescan && contextTargets(for: id).contains(where: isEditable)
    }

    /// The origin of **Image > Create Layout…**: the selection when it is not empty, else the current category or
    /// collection. Nil when no origin applies or it has no photo to lay out.
    var layoutMenuOrigin: LayoutOrigin? {
        let origin: LayoutOrigin
        if !selection.isEmpty {
            origin = .selection
        } else {
            switch selectedItem {
            case .category(let c): origin = .category(c)
            case .collection(let c): origin = .collection(c)
            default: return nil
            }
        }
        return canCreateLayout(from: origin) ? origin : nil
    }

    func requestLayoutFromMenu() {
        if let origin = layoutMenuOrigin { requestLayout(from: origin) }
    }

    /// Opens the layout editor on the photos of `origin`. A draft with photos makes the screen ask first.
    func requestLayout(from origin: LayoutOrigin) {
        guard canCreateLayout(from: origin) else { return }
        if let draft = review.session.layoutDraft, !draft.photoIDs.isEmpty {
            askingToContinueLayout = origin
        } else {
            openLayout(.new(photos: layoutPhotoIDs(of: origin), title: layoutTitle(of: origin)), origin: origin)
        }
    }

    /// The message of the "Continue your last layout?" alert: how many photos the draft has.
    var continueLayoutMessage: String { CountText.lastLayout(review.session.layoutDraft?.photoIDs.count ?? 0) }

    /// Answers the question with **Continue Layout**: opens the draft.
    func continueLayout() {
        guard let origin = askingToContinueLayout else { return }
        askingToContinueLayout = nil
        guard canSortOrRescan, let draft = review.session.layoutDraft else { return }
        openLayout(draft, origin: origin)
    }

    /// Answers the question with **Start New**: opens a new layout on the photos of the origin.
    func startNewLayout() {
        guard let origin = askingToContinueLayout else { return }
        askingToContinueLayout = nil
        guard canCreateLayout(from: origin) else { return }
        openLayout(.new(photos: layoutPhotoIDs(of: origin), title: layoutTitle(of: origin)), origin: origin)
    }

    /// Answers the question with **Cancel**. The draft stays.
    func cancelLayoutRequest() { askingToContinueLayout = nil }

    /// The title of a new layout: the category or collection name, or empty for a selection.
    private func layoutTitle(of origin: LayoutOrigin) -> String {
        switch origin {
        case .selection: ""
        case .category(let c): review.session.categories.first { $0.id == c }?.displayName ?? ""
        case .collection(let c): collections.first { $0.id == c }?.name ?? ""
        }
    }

    /// The readable images of `origin` that are not in the Trash: the selection in grid order, a category in
    /// the order of its grid, or a collection in the order of its members.
    private func layoutPhotoIDs(of origin: LayoutOrigin) -> [MediaID] {
        switch origin {
        case .selection: selectedInGridOrder.filter(isEditable)
        case .category(let c): layoutPhotoIDs(of: .category(c) as SidebarItem)
        case .collection(let c): layoutPhotoIDs(of: .collection(c) as SidebarItem)
        }
    }

    private func layoutPhotoIDs(of item: SidebarItem) -> [MediaID] {
        let session = review.session
        if case .collection(let c) = item {
            return CollectionService.visibleMembers(of: c, in: session).filter(isEditable)
        }
        let files = session.visibleMedia.filter {
            Self.includes($0, state: session.states[$0.id], in: item) && isEditable($0.id)
        }
        return sorted(files, session: session)
    }

    private func sourceID(of origin: LayoutOrigin) -> String {
        switch origin {
        case .selection: "all"
        case .category(let c): "category:\(c.uuidString)"
        case .collection(let c): "collection:\(c.uuidString)"
        }
    }

    private func openLayout(_ document: LayoutDocument, origin: LayoutOrigin) {
        guard canSortOrRescan else { return }
        func option(_ id: String, _ title: String, _ item: SidebarItem) -> LayoutSourceOption {
            LayoutSourceOption(id: id, title: title, photos: layoutPhotoIDs(of: item).compactMap { id in
                mediaByID[id].map { LayoutPhoto(id: id, fileName: Self.fileName($0)) }
            })
        }
        let sources = [option("all", String(localized: "All Photos"), .all)]
            + categories.map { option(sourceID(of: .category($0.id)), "\($0.emoji) \($0.displayName)", .category($0.id)) }
            + collections.map { option(sourceID(of: .collection($0.id)), $0.name, .collection($0.id)) }
        let fileNames = Dictionary(
            mediaByID.values.filter { $0.kind == .image }.map { ($0.id, Self.fileName($0)) },
            uniquingKeysWith: { first, _ in first })
        itemAfterClose = nil
        askingToContinueLayout = nil
        activeEditor = .layout(LayoutEditorViewModel(
            document: document, sources: sources, startSource: sourceID(of: origin), service: layoutExport,
            source: source, protected: protectedFilesProvider, fileNames: fileNames,
            saveDraft: { [weak self] in self?.review.saveLayoutDraft($0) },
            chooseDestination: chooseLayoutDestination,
            revealURL: { [weak self] in self?.revealURLs([$0]) },
            onClose: { [weak self] in self?.closeEditor() },
            onCancelClose: { [weak self] in self?.itemAfterClose = nil },
            isAvailable: { [weak self] id in
                guard let self else { return false }
                return !self.review.session.trashed.contains { $0.mediaID == id }
            }))
    }

    // MARK: - Photo actions

    /// True if at least 1 selected photo is in "Needs Review", so **Accept Best Guess** has work to do.
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
        guard bodyKind != .recentlyDeleted, !selection.isEmpty, (1...9).contains(n), n <= categories.count
        else { return false }
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
        guard bodyKind != .recentlyDeleted, !ids.isEmpty else { return false }
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
        if runs { watchTrashErrors(title: String(localized: "Undo")) }
    }

    func redo() {
        let runs = review.canRedo
        review.redo()
        if runs { watchTrashErrors(title: String(localized: "Redo")) }
    }

    /// Moves the selected photos to the Trash, with no confirmation (spec 3.3). They leave every list; **Undo**
    /// puts them back. A photo that cannot move stays, and `trashMessage` tells why.
    func trashSelection() async {
        let ids = selectedInGridOrder
        guard bodyKind != .recentlyDeleted, !ids.isEmpty else { return }
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
    func showTrashErrors(_ errors: [TrashError], title: String = String(localized: "Move to Trash")) {
        guard let message = Self.summary(of: errors) else { return }
        trashAlertTitle = title
        trashMessage = message
    }

    /// The text of the first error, and "and <n> more" for the others. Nil for no error.
    private static func summary(of errors: [TrashError]) -> String? {
        guard let first = errors.first else { return nil }
        let more = errors.count - 1
        let message = CoreErrorMessages.text(for: first)
        return more > 0 ? String(localized: "\(message) (and \(more) more)") : message
    }

    // MARK: - Category edits

    /// Why the last folder rename failed, or nil. The alert of the review screen shows it.
    var folderErrorMessage: String? { review.folderError.map(CoreErrorMessages.text(for:)) }

    func dismissFolderError() { review.dismissFolderError() }

    var canDeleteCategory: Bool { review.canDeleteCategory }

    /// The title of the confirmation dialog before a delete (spec 3.3).
    func deleteConfirmation(for c: CategoryID) -> String {
        String(localized: "Delete \(categoryName(c))?")
    }

    /// The warning of that dialog: the photos go to the Trash and the folder goes too.
    func deleteMessage(for c: CategoryID) -> String {
        let folder = SortPlanner.folderNames(for: review.session.categories)[c] ?? categoryName(c)
        let photos = CountText.photos(review.photoIDs(in: c).count)
        return String(localized: "\(photos) in this category move to the Trash, and the folder \"\(folder)\" is deleted. Press ⌘Z to put the photos back. A file that is not in this category stays, and so does the folder.")
    }

    private func categoryName(_ c: CategoryID) -> String {
        review.session.categories.first { $0.id == c }?.displayName ?? ""
    }

    /// Deletes `c`: its photos go to the Trash, and its folder goes. The Needs Review list shows if `c` was showing.
    func deleteCategory(_ c: CategoryID) async {
        guard canDeleteCategory else { return }
        if selectedItem == .category(c) { selectedItem = .notSure }
        clearSelection()
        showTrashErrors(await review.deleteCategoryAndPhotos(c))
        closeEditIfCategoryIsGone()
    }

    /// The categories that `c` can merge into, in sidebar order.
    func mergeTargets(for c: CategoryID) -> [PicnestCore.Category] {
        categories.filter { $0.id != c }
    }

    func merge(_ c: CategoryID, into target: CategoryID) {
        review.merge(c, into: target)
        if selectedItem == .category(c) { selectedItem = .category(target) }
        closeEditIfCategoryIsGone()
    }

    /// Closes the Edit Category sheet when its category no longer exists (merged, deleted, or undone).
    func closeEditIfCategoryIsGone() {
        if let editing = editingCategory, !categories.contains(where: { $0.id == editing }) { editingCategory = nil }
    }

    /// Renames `c`. A name that is empty after trimming is ignored.
    func renameCategory(_ c: CategoryID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        review.rename(c, to: name)
    }

    /// The category that the Edit Category sheet shows, or nil while the sheet is closed.
    var editingCategory: CategoryID?

    /// The category that waits for the answer of the delete confirmation, or nil.
    var deletingCategory: CategoryID?

    /// Why a category name cannot be used. `message` is the text under the name field.
    enum CategoryNameIssue: Equatable {
        case empty, duplicate

        var message: LocalizedStringKey {
            switch self {
            case .empty: "Enter a name."
            case .duplicate: "A category with this name already exists."
            }
        }
    }

    /// Checks a category name. `excluding` is the category that gets the name, so it does not clash with itself.
    /// The folder rules of `SortPlanner` replace "/", ":" and a leading ".", so every non-empty name makes a folder.
    func validateCategoryName(_ name: String, excluding: CategoryID?) -> CategoryNameIssue? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let wanted = Self.normalizedName(trimmed)
        let others = review.session.categories.filter { $0.id != excluding }
        if others.contains(where: { Self.normalizedName($0.displayName) == wanted }) { return .duplicate }
        return nil
    }

    /// Trimmed, NFC, and without case and diacritics, for the comparison of names.
    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The folder of `c` relative to the source folder, for example "Travel".
    func categoryFolderName(_ c: CategoryID) -> String {
        SortPlanner.folderNames(for: review.session.categories)[c] ?? categoryName(c)
    }

    /// Save is on when the name is valid and the name or the icon changed.
    func canSaveCategoryEdit(_ c: CategoryID, name: String, emoji: String) -> Bool {
        guard let category = review.session.categories.first(where: { $0.id == c }),
              validateCategoryName(name, excluding: c) == nil else { return false }
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard emoji == category.emoji || Self.isSingleEmoji(emoji) else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != category.displayName || emoji != category.emoji
    }

    /// The Save button of the Edit Category sheet. Returns false, and does nothing, if `canSaveCategoryEdit` is false.
    @discardableResult
    func saveCategoryEdit(_ c: CategoryID, name: String, emoji: String) -> Bool {
        guard canSaveCategoryEdit(c, name: name, emoji: emoji),
              let category = review.session.categories.first(where: { $0.id == c }) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != category.displayName { renameCategory(c, to: trimmed) }
        if emoji.trimmingCharacters(in: .whitespacesAndNewlines) != category.emoji { setEmoji(c, emoji) }
        return true
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

    // MARK: - Favorites and collections

    /// The collections in sidebar order.
    var collections: [PhotoCollection] {
        review.session.collections.sorted { $0.order < $1.order }
    }

    func isFavorite(_ id: MediaID) -> Bool { review.session.favoriteIDs.contains(id) }

    /// True when `ids` has photos and all of them are favorites: the toggle then removes them.
    func allFavorites(_ ids: [MediaID]) -> Bool { !ids.isEmpty && ids.allSatisfy(isFavorite) }

    /// The heart of 1 photo. It does not change the selection.
    func toggleFavorite(_ id: MediaID) { review.toggleFavorite([id]) }

    /// The key `.` and the favorite items work on the selection, but not in Recently Deleted.
    var canFavoriteSelection: Bool { bodyKind != .recentlyDeleted && !selection.isEmpty }

    /// True in a collection: the photos can leave it.
    var canRemoveFromCollection: Bool {
        if case .collection = selectedItem { true } else { false }
    }

    /// Opens the new collection sheet with the selection in it.
    func requestNewCollectionFromSelection() {
        let ids = selectedInGridOrder
        guard !ids.isEmpty else { return }
        requestNewCollection(adding: ids)
    }

    /// Adds the selection to the favorites, or removes it when every selected photo is a favorite.
    func toggleFavoriteSelection() {
        let ids = selectedInGridOrder
        guard bodyKind != .recentlyDeleted, !ids.isEmpty else { return }
        review.toggleFavorite(ids)
    }

    func addSelection(to c: CollectionID) {
        let ids = selectedInGridOrder
        guard !ids.isEmpty else { return }
        review.addToCollection(ids, c)
    }

    /// Only in a collection. The photos stay in their folders and in every other list.
    func removeSelectionFromCollection() {
        guard case .collection(let c) = selectedItem else { return }
        let ids = selectedInGridOrder
        guard !ids.isEmpty else { return }
        review.removeFromCollection(ids, c)
        clearSelection()
    }

    /// Photos dropped on a sidebar collection. Returns false for an empty drop or an unknown collection.
    @discardableResult
    func dropOnCollection(_ ids: [MediaID], _ c: CollectionID) -> Bool {
        guard bodyKind != .recentlyDeleted, !ids.isEmpty,
              review.session.collections.contains(where: { $0.id == c }) else { return false }
        review.addToCollection(ids, c)
        return true
    }

    // MARK: - Add Photos

    /// The open Add Photos sheet, or nil.
    var addingPhotos: AddPhotosTarget?

    /// The visible photos that are not in `target` yet, by file name, that match `search`.
    func addPhotosCandidates(for target: AddPhotosTarget, matching search: String = "") -> [MediaID] {
        let session = review.session
        let needle = SearchText.needle(search)
        let item: SidebarItem = switch target {
        case .category(let c): .category(c)
        case .collection(let c): .collection(c)
        }
        let members = Self.members(of: item, in: session)
        return session.visibleMedia
            .filter { media in
                !Self.includes(media, state: session.states[media.id], in: item, members: members)
                    && (needle.map { Self.matches(media, needle: $0) } ?? true)
            }
            .sorted {
                let (a, b) = (Self.fileName($0), Self.fileName($1))
                return a != b ? a.localizedStandardCompare(b) == .orderedAscending : $0.id < $1.id
            }
            .map(\.id)
    }

    /// Adds `picks` to `target`, in the order of `addPhotosCandidates`. A category target makes manual picks (the files move at **Done**). A collection target adds members.
    func addPhotos(_ picks: some Collection<MediaID>, to target: AddPhotosTarget) {
        // The grid order, so the members and the picks do not depend on the order of the taps.
        let picked = Set(picks)
        let ids = addPhotosCandidates(for: target).filter(picked.contains)
        switch target {
        case .category(let c): review.move(ids, to: c)
        case .collection(let c): review.addToCollection(ids, c)
        }
        addingPhotos = nil
    }

    /// The collection that `selectedItem` shows, or nil for any other item.
    var selectedCollection: PhotoCollection? {
        guard case .collection(let c) = selectedItem else { return nil }
        return collections.first { $0.id == c }
    }

    /// The name for the collection sheet that opens when the Edit Category sheet is gone, or nil.
    private var pendingCollectionName: String?

    /// **Create a collection instead** in the Edit Category sheet. The category stays as it is. The sheet closes
    /// first, then `openPendingCollection` opens the collection sheet, so the 2 sheets do not overlap.
    func createCollectionInstead(of c: CategoryID) {
        guard let category = categories.first(where: { $0.id == c }) else { return }
        pendingCollectionName = category.displayName
        editingCategory = nil
    }

    /// Runs when the Edit Category sheet is gone. Opens the collection sheet of `createCollectionInstead`, once.
    func openPendingCollection() {
        guard let name = pendingCollectionName else { return }
        pendingCollectionName = nil
        requestNewCollection(name: name, adding: [])
    }

    /// The open collection sheet, or nil.
    var editingCollection: CollectionEditor?
    /// The collection that waits for the answer of the delete confirmation, or nil.
    var deletingCollection: CollectionID?

    /// Opens the sheet for a new collection. `adding` are the photos that it starts with.
    func requestNewCollection(name: String = "", adding: [MediaID]) {
        editingCollection = .new(name: name, adding: adding)
    }

    func requestRenameCollection(_ c: CollectionID) {
        guard review.session.collections.contains(where: { $0.id == c }) else { return }
        editingCollection = .rename(c)
    }

    /// The name that the open sheet starts with.
    var collectionSheetName: String {
        switch editingCollection {
        case .new(let name, _): name
        case .rename(let c): collections.first { $0.id == c }?.name ?? ""
        case nil: ""
        }
    }

    /// The collection that the open sheet renames. Its own name is not a duplicate. Nil for a new collection.
    var collectionSheetExcluding: CollectionID? {
        if case .rename(let c) = editingCollection { c } else { nil }
    }

    /// The title of the confirmation dialog before a collection is deleted.
    func deleteCollectionTitle(for c: CollectionID) -> String {
        let name = collections.first { $0.id == c }?.name ?? ""
        return String(localized: "Delete the collection “\(name)”?")
    }

    func validateCollectionName(_ name: String, excluding: CollectionID?) -> CollectionNameIssue? {
        CollectionService.validateName(name, excluding: excluding, among: review.session.collections)
    }

    /// The Create or Save button. Returns false, and keeps the sheet, when the name has an issue.
    @discardableResult
    func saveCollection(name: String) -> Bool {
        switch editingCollection {
        case .new(_, let adding):
            guard review.createCollection(name: name, adding: adding) != nil else { return false }
        case .rename(let c):
            guard validateCollectionName(name, excluding: c) == nil else { return false }
            review.renameCollection(c, to: name)
        case nil:
            return false
        }
        editingCollection = nil
        return true
    }

    /// Deletes `c`. The photos stay in their folders. If `c` shows, All Photos shows.
    func deleteCollection(_ c: CollectionID) {
        if selectedItem == .collection(c) { selectedItem = .all }
        review.deleteCollection(c)
        deletingCollection = nil
        closeCollectionSheetIfGone()
    }

    private func closeCollectionSheetIfGone() {
        if case .rename(let c) = editingCollection, !review.session.collections.contains(where: { $0.id == c }) {
            editingCollection = nil
        }
    }

    // MARK: - Recently Deleted

    /// The text of the Put Back alert, or nil. It names the first error and counts the others.
    var putBackErrorMessage: String?

    /// Puts the selected photos back to their places. A photo that cannot come back stays in the list.
    func putBackSelection() {
        let ids = selectedInGridOrder
        guard !ids.isEmpty else { return }
        review.putBack(ids)
        clearSelection()
        let review = review
        undoWatch = Task { [weak self] in
            await review.settled()
            self?.putBackErrorMessage = Self.summary(of: review.lastPutBackErrors)
        }
    }

    /// The trashed photos, newest first, then by id, that match `search`.
    private func recentlyDeletedIDs(session: Session, search: String) -> [MediaID] {
        let needle = SearchText.needle(search)
        let names = mediaByID
        return session.trashed
            .filter { record in
                guard let needle else { return true }
                return names[record.mediaID].map { Self.matches($0, needle: needle) } ?? false
            }
            .sorted { $0.time != $1.time ? $0.time > $1.time : $0.mediaID < $1.mediaID }
            .map(\.mediaID)
    }

    // MARK: - Private

    /// Drops both caches once after `review.session` changed, and watches the session again.
    private func refreshIfSessionChanged() {
        guard sessionChanged else { return }
        sessionChanged = false
        closeEditIfCategoryIsGone()
        closeCollectionSheetIfGone()
        watchSession()
        cache = nil
        groupsCache = nil
        // A folder rename gave photos new paths, so the ids of the selection are old.
        if seenMediaRevision != review.mediaRevision {
            seenMediaRevision = review.mediaRevision
            selection = []
            anchor = nil
        }
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

    /// A new search text or issue filter hides photos: they leave the selection now, so no action reaches them.
    private func dropSelectionHiddenByFilter() {
        guard !selection.isEmpty else { return }
        dropHiddenSelection(visible: visibleIDs)
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

    private static func matches(_ media: MediaFile, needle: String) -> Bool {
        SearchText.matches(fileName(media), needle: needle)
    }

    /// The photos that `item` lists by membership: the visible favorites or the visible members of a collection.
    /// Nil for any other item.
    private static func members(of item: SidebarItem, in session: Session) -> Set<MediaID>? {
        switch item {
        case .favorites: CollectionService.visibleFavorites(in: session)
        case .collection(let c): Set(CollectionService.visibleMembers(of: c, in: session))
        default: nil
        }
    }

    private static func includes(
        _ media: MediaFile, state: PhotoState?, in item: SidebarItem, members: Set<MediaID>? = nil
    ) -> Bool {
        switch item {
        case .favorites, .collection: return members?.contains(media.id) == true
        case .recentlyDeleted: return false  // The trashed photos are not in `visibleMedia`.
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

    /// "or <name> <n>%" in Needs Review if there is a second guess; else the date, or "no date" when only
    /// the modification time is known (spec 3.3).
    private func secondLine(_ id: MediaID, state: PhotoState?, session: Session) -> String {
        if selectedItem == .notSure, let a = Self.assignment(state), let second = a.secondCategoryID,
           let category = session.categories.first(where: { $0.id == second }),
           let percent = classify.secondPercent(of: a) {
            return String(localized: "or \(category.displayName) \(percent)%")
        }
        guard let date = session.scan.dates[id], date.source != .modificationTime else { return Self.noDate }
        return date.date.formatted(.dateTime.year().month().day())
    }

    private static func assignment(_ state: PhotoState?) -> Assignment? {
        switch state {
        case .auto(let a), .heldNotSure(let a): a
        default: nil
        }
    }
}
