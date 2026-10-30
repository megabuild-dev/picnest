import Foundation
import Observation

/// Owns the open session during review (spec 3.3, 3.4, 4.7).
/// Each action changes `session` at once, pushes an undo snapshot, then classifies the photos again
/// on a background task and saves the session. Only the result of the newest change is applied.
@MainActor
@Observable
public final class ReviewService {
    public static let undoLimit = 100

    public private(set) var session: Session
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    /// The error of the last failed save, or nil after a good save.
    public private(set) var saveError: (any Error)?
    /// The photos that the last undo could not put back, or the last redo could not trash again
    /// (spec 7.4). Those photos stay as they were. Empty after an undo or redo with no error.
    public private(set) var lastUndoErrors: [TrashError] = []
    /// True while a Move to Trash, a clean-up, or a Trash undo or redo runs (final review I1). The app turns
    /// off Sort, Rescan, Done, and Undo Last Sort meanwhile; `settled()` waits until it is false.
    public private(set) var isMovingFiles = false
    /// Every scanned photo, trashed ones too, by id. It changes only when photos get new paths
    /// (`mediaRevision` goes up then): a folder rename or Done.
    public private(set) var mediaByID: [MediaID: MediaFile]
    public private(set) var mediaRevision = 0
    /// Why the last category folder rename failed, or nil. The category keeps its name then.
    public private(set) var folderError: String?

    /// False when only 1 category is left. `delete` ignores the last category.
    public var canDeleteCategory: Bool { session.categories.count > 1 }

    @ObservationIgnored private let source: URL
    @ObservationIgnored private var images: [MediaID: Vector]
    @ObservationIgnored private var prompts: [CategoryID: [Vector]]
    @ObservationIgnored private let classify: ClassifyService
    @ObservationIgnored private let sessions: SessionRepository
    @ObservationIgnored private let embeddings: EmbeddingRepository
    @ObservationIgnored private let trash: TrashService
    @ObservationIgnored private let folders: CategoryFolderService
    @ObservationIgnored private let candidates: CandidateRepository
    @ObservationIgnored private let hashes: HashRepository
    @ObservationIgnored private let imageFiles: ImageRepository
    /// True after `close()`: `save()` writes nothing until `reopen()`.
    @ObservationIgnored private var isClosed = false
    /// True when a save was skipped while closed. `reopen()` saves then.
    @ObservationIgnored private var unsavedWhileClosed = false
    /// The result of the last `findDuplicates`. Clean-up never trashes the Keep photo of its exact groups.
    @ObservationIgnored private var lastDuplicates: [DuplicateGroup] = []
    /// The pixel sizes that the last `findDuplicates` read.
    @ObservationIgnored private var pixelSizes: [MediaID: PixelSize] = [:]
    @ObservationIgnored private var undoStack: [ReviewChange] = []
    @ObservationIgnored private var redoStack: [ReviewChange] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// The count of Trash moves that run now. Undo and redo wait for 0, so the undo stack keeps its order.
    @ObservationIgnored private var fileOperations = 0
    /// The latest undo or redo that moves files.
    @ObservationIgnored private var fileTask: Task<Void, Never>?
    /// The photos whose move to the Trash runs now. A second `moveToTrash` skips them.
    @ObservationIgnored private var trashing: Set<MediaID> = []
    /// Goes up each time a new action clears the redo stack.
    @ObservationIgnored private var redoEpoch = 0
    /// The count of running Trash moves, clean-ups, and Trash undo or redo steps. Sets `isMovingFiles`.
    @ObservationIgnored private var movingFiles = 0 {
        didSet {
            let moving = movingFiles > 0
            if isMovingFiles != moving { isMovingFiles = moving }
            if !moving {
                let waiters = idleWaiters
                idleWaiters = []
                for waiter in waiters { waiter.resume() }
            }
        }
    }
    /// The `settled()` calls that wait until `movingFiles` is 0.
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        session: Session, source: URL, images: [MediaID: Vector], prompts: [CategoryID: [Vector]],
        classify: ClassifyService, sessions: SessionRepository, embeddings: EmbeddingRepository,
        trash: TrashService = TrashService(), candidates: CandidateRepository = CandidateRepository(),
        hashes: HashRepository? = nil, imageFiles: ImageRepository = ImageRepository(),
        folders: CategoryFolderService = CategoryFolderService()
    ) {
        self.folders = folders
        self.session = session
        mediaByID = Self.index(session.scan.media)
        self.source = source
        self.images = images
        self.prompts = prompts
        self.classify = classify
        self.sessions = sessions
        self.embeddings = embeddings
        self.trash = trash
        self.candidates = candidates
        // The hash cache lives in the session folder by default (spec 4.9).
        self.hashes = hashes ?? HashRepository(cacheDirectory: sessions.directory(for: source))
        self.imageFiles = imageFiles
    }

    /// Loads image vectors (from the cache) and the prompt vectors of every category.
    public static func open(
        session: Session, source: URL, embeddings: EmbeddingRepository, classify: ClassifyService,
        sessions: SessionRepository, trash: TrashService = TrashService(),
        candidates: CandidateRepository = CandidateRepository(), hashes: HashRepository? = nil,
        imageFiles: ImageRepository = ImageRepository(), folders: CategoryFolderService = CategoryFolderService()
    ) async throws -> ReviewService {
        let files = session.readableImages
        let (vectors, _) = try await embeddings.embeddings(for: files, source: source) { _, _ in }
        var prompts: [CategoryID: [Vector]] = [:]
        for category in session.categories {
            prompts[category.id] = try await embeddings.textEmbeddings(category.prompts)
        }
        return ReviewService(
            session: session, source: source, images: vectors, prompts: prompts,
            classify: classify, sessions: sessions, embeddings: embeddings, trash: trash, candidates: candidates,
            hashes: hashes, imageFiles: imageFiles, folders: folders)
    }

    /// Waits until no file moves (Move to Trash, clean-up, Trash undo or redo), and the background
    /// recalculation and save of the latest change are done.
    public func settled() async {
        while true {
            if let task = fileTask {
                await task.value
                if fileTask == task { fileTask = nil }
            } else if movingFiles > 0 {
                await withCheckedContinuation { idleWaiters.append($0) }
            } else if let task = pending {
                await task.value
                if pending == task, fileTask == nil, movingFiles == 0 { return }
            } else {
                return
            }
        }
    }

    /// Records the time of a sort in the session and saves it (spec 9.1). Review undo does not change it.
    public func markSorted(at date: Date) {
        session.sortedAt = date
        save()
    }

    /// Clears the time of the sort after **Undo Last Sort**, and saves the session (spec 9.1).
    public func clearSorted() {
        session.sortedAt = nil
        save()
    }

    // MARK: - Organize in place

    /// Re-keys the open session after an in-place organize (spec 7.2): the moved files get their new
    /// paths in `scan.media` (id and relativePath), `scan.dates`, `states`, and every `exampleIDs`.
    /// Duplicate-group keys are dropped, because a moved group is a new group. The embedding cache is
    /// re-keyed, so the next open does not embed the photos again. Then the session is saved.
    public func applyOrganize(_ moves: [OrganizeMove]) async {
        guard !moves.isEmpty else { return }
        var map: [MediaID: String] = [:]
        for move in moves { map[move.mediaID] = move.to }
        await rekey(map)
    }

    /// Gives photos new paths: `map` holds the new path of each moved photo. Re-keys `scan.media` (id and
    /// relativePath), `dates`, `states`, `trashed`, every `exampleIDs`, the image vectors, and the embedding
    /// cache. Drops the duplicate state, because a moved group is a new group. Then saves the session.
    private func rekey(_ map: [MediaID: String]) async {
        var media: [MediaFile] = []
        media.reserveCapacity(session.scan.media.count)
        var keyMap: [String: String] = [:]
        for file in session.scan.media {
            guard let to = map[file.id] else { media.append(file); continue }
            let moved = MediaFile(id: to, relativePath: to, kind: file.kind, size: file.size, modified: file.modified)
            keyMap[file.cacheKey] = moved.cacheKey
            media.append(moved)
        }
        var dates: [MediaID: PhotoDate] = [:]
        for (id, date) in session.scan.dates { dates[map[id] ?? id] = date }
        var states: [MediaID: PhotoState] = [:]
        for (id, state) in session.states { states[map[id] ?? id] = state }
        var categories = session.categories
        for i in categories.indices { categories[i].exampleIDs = categories[i].exampleIDs.map { map[$0] ?? $0 } }

        session.scan.media = media.sorted { $0.id < $1.id }
        session.scan.dates = dates
        session.states = states
        session.categories = categories
        session.trashed = session.trashed.map { record in
            var moved = record
            moved.mediaID = map[record.mediaID] ?? record.mediaID
            return moved
        }
        session.notDuplicateKeys = []
        lastDuplicates = []
        pixelSizes = [:]
        var vectors: [MediaID: Vector] = [:]
        for (id, vector) in images { vectors[map[id] ?? id] = vector }
        images = vectors
        mediaByID = Self.index(session.scan.media)
        mediaRevision += 1
        await embeddings.rekey(keyMap)
        save()
    }

    private static func index(_ media: [MediaFile]) -> [MediaID: MediaFile] {
        Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stops all saves of the session (Start Over, spec 3.3). A change made after this stays in memory only,
    /// so it cannot write `session.json` again after the start over deletes it. Call `reopen()` if the start
    /// over fails.
    public func close() {
        isClosed = true
    }

    /// Lets the session save again after `close()`, and saves the changes made while it was closed.
    public func reopen() {
        guard isClosed else { return }
        isClosed = false
        if unsavedWhileClosed { save() }
    }

    /// Saves the session again after a failed save (**Try Again** in the save alert).
    public func retrySave() {
        save()
    }

    /// Hides the save error. The next failed save sets it again.
    public func dismissSaveError() {
        saveError = nil
    }

    // MARK: - Photo actions

    /// Manual pick: the photos go to `c` and become examples of `c` only.
    public func move(_ ids: [MediaID], to c: CategoryID) {
        guard session.categories.contains(where: { $0.id == c }) else { return }
        let ids = known(ids)
        guard !ids.isEmpty else { return }
        perform { categories, states in
            Self.pick(ids.map { ($0, c) }, categories: &categories, states: &states)
        }
    }

    /// Not-sure photos go to their best category as manual picks and examples (spec 4.7).
    /// Other photos are ignored.
    public func acceptBestGuess(_ ids: [MediaID]) {
        let existing = Set(session.categories.map(\.id))
        let picks: [(MediaID, CategoryID)] = known(ids).compactMap { id in
            guard let state = session.states[id], state.isNotSure,
                  let a = Self.assignment(state), existing.contains(a.categoryID) else { return nil }
            return (id, a.categoryID)
        }
        guard !picks.isEmpty else { return }
        perform { categories, states in
            Self.pick(picks, categories: &categories, states: &states)
        }
    }

    public func acceptAllNotSure() {
        acceptBestGuess(session.states.filter { $0.value.isNotSure }.keys.sorted())
    }

    public func acceptGroup(bestCategory: CategoryID) {
        acceptBestGuess(notSureGroups.first { $0.category == bestCategory }?.ids ?? [])
    }

    public func dontMove(_ ids: [MediaID]) {
        let ids = known(ids)
        guard !ids.isEmpty else { return }
        perform { categories, states in
            for id in ids { states[id] = .dontMove }
            let set = Set(ids)
            for i in categories.indices { categories[i].exampleIDs.removeAll { set.contains($0) } }
        }
    }

    /// Moves the photos to the macOS Trash (spec 3.3, 7.4). The file moves run off the main actor. The
    /// photos that moved become 1 undo step: they leave `states` and every `exampleIDs`, and go to
    /// `session.trashed`. Then the photos are classified again and the session is saved.
    /// Returns 1 `cannotTrash` error for each photo that did not move. Those photos do not change.
    /// Unknown ids, trashed ids, and ids whose move to the Trash runs now are ignored.
    @discardableResult
    public func moveToTrash(_ ids: [MediaID]) async -> [TrashError] {
        await trashFiles(ids, newAction: true)
    }

    // MARK: - Category actions

    /// A new category with 1 prompt, "a photo of <name>" (spec 4.4), at the end of the order.
    @discardableResult
    public func addCategory(name: String, emoji: String) -> CategoryID {
        let id = CategoryID()
        let prompt = "a photo of \(name)"
        let folder = SortPlanner.uniqueFolderName(for: name, among: session.categories)
        let embeddings = embeddings
        perform(prepare: { [weak self] in
            guard let vectors = try? await embeddings.textEmbeddings([prompt]) else { return }
            self?.prompts[id] = vectors
        }) { categories, _ in
            let order = (categories.map(\.order).max() ?? -1) + 1
            categories.append(Category(
                id: id, displayName: name, emoji: emoji, prompts: [prompt], exampleIDs: [], order: order,
                folderName: folder))
        }
        makeFolders([folder])
        return id
    }

    /// Renames `c`, and its folder if the folder is on disk. A folder rename is not undoable: the photos
    /// in it get new paths, so old undo steps do not fit any more. It clears the undo history. If the
    /// folder cannot move, the category keeps its name and `folderError` says why.
    public func rename(_ c: CategoryID, to name: String) {
        guard let category = session.categories.first(where: { $0.id == c }) else { return }
        let old = SortPlanner.folderNames(for: session.categories)[c] ?? SortPlanner.folderName(for: category.displayName)
        let new = SortPlanner.uniqueFolderName(for: name, among: session.categories, excluding: c)
        guard old != new, folders.exists(old, in: source) else {
            editCategory(c) { $0.displayName = name; $0.folderName = new }
            return
        }
        runFileTask { await $0.renameFolder(c, to: name, from: old, newFolder: new) }
    }

    public func dismissFolderError() {
        folderError = nil
    }

    private func renameFolder(_ c: CategoryID, to name: String, from old: String, newFolder new: String) async {
        let folders = folders, source = source
        let result = await Task.detached(priority: .userInitiated) {
            Result { try folders.rename(old, to: new, in: source) }
        }.value
        switch result {
        case .failure(let error):
            folderError = "The folder \"\(old)\" could not be renamed to \"\(new)\": \(error.localizedDescription)"
        case .success(let moved):
            guard let i = session.categories.firstIndex(where: { $0.id == c }) else { return }
            session.categories[i].displayName = name
            session.categories[i].folderName = new
            guard moved else { save(); return }
            undoStack.removeAll()
            redoStack.removeAll()
            redoEpoch += 1
            await rekey(Self.pathChanges(in: session.scan.media, from: old, to: new))
        }
    }

    /// The new path of each photo in the folder `old` when that folder becomes `new`.
    private static func pathChanges(in media: [MediaFile], from old: String, to new: String) -> [MediaID: String] {
        let prefix = old + "/"
        var map: [MediaID: String] = [:]
        for file in media where file.relativePath.hasPrefix(prefix) {
            map[file.id] = new + "/" + file.relativePath.dropFirst(prefix.count)
        }
        return map
    }

    public func setEmoji(_ c: CategoryID, _ e: String) {
        editCategory(c) { $0.emoji = e }
    }

    /// Puts the listed categories first, in the given order. Unknown ids are ignored.
    /// Categories that are not listed keep their relative order after them.
    public func reorder(_ ids: [CategoryID]) {
        perform { categories, _ in
            let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            let first = ids.filter { byID[$0] != nil }.uniqued()
            let listed = Set(first)
            let rest = categories.sorted { $0.order < $1.order }.map(\.id).filter { !listed.contains($0) }
            categories = (first + rest).enumerated().map { index, id in
                var category = byID[id]!
                category.order = index
                return category
            }
        }
    }

    /// Manual picks of `from` become manual picks of `into`; examples move; `from` is removed.
    public func merge(_ from: CategoryID, into: CategoryID) {
        guard from != into,
              session.categories.contains(where: { $0.id == from }),
              session.categories.contains(where: { $0.id == into }) else { return }
        perform { categories, states in
            for (id, state) in states {
                switch state {
                case .manual(from): states[id] = .manual(into)
                case .auto(let a): states[id] = .auto(Self.remap(a, from: from, into: into))
                case .heldNotSure(let a): states[id] = .heldNotSure(Self.remap(a, from: from, into: into))
                default: break
                }
            }
            let moved = categories.first { $0.id == from }?.exampleIDs ?? []
            if let i = categories.firstIndex(where: { $0.id == into }) {
                let present = Set(categories[i].exampleIDs)
                categories[i].exampleIDs += moved.filter { !present.contains($0) }
            }
            categories.removeAll { $0.id == from }
            Self.renumber(&categories)
        }
    }

    /// The photos that show in category `c`: manual picks and certain guesses. Trashed photos are not in it.
    public func photoIDs(in c: CategoryID) -> [MediaID] {
        session.visibleMedia.map(\.id).filter { id in
            switch session.states[id] {
            case .manual(c): true
            case .auto(let a): a.categoryID == c && !a.uncertain
            default: false
            }
        }
    }

    /// **Delete** with a confirmation: the photos of `c` go to the Trash, then `c` is deleted, then its folder
    /// is removed if it is empty. Each of the 2 steps can be undone (the photos come back from the Trash;
    /// the category comes back, its folder is made again when a photo returns). A photo that cannot move
    /// stays and goes to Not sure, and its folder stays: `folderError` says so. Does nothing for the last
    /// category.
    public func deleteCategoryAndPhotos(_ c: CategoryID) async -> [TrashError] {
        guard canDeleteCategory, let folder = SortPlanner.folderNames(for: session.categories)[c] else { return [] }
        let errors = await trashFiles(photoIDs(in: c), newAction: true)
        delete(c)
        let folders = folders, source = source
        let removal = await Task.detached(priority: .userInitiated) { folders.removeIfEmpty(folder, in: source) }.value
        if case .kept(let others) = removal {
            folderError = others > 0
                ? "The folder \"\(folder)\" stays, because it holds \(others) file\(others == 1 ? "" : "s") that were not in this category."
                : "The folder \"\(folder)\" could not be removed."
        }
        return errors
    }

    /// All photos of `c`, also manual picks, go to Not sure and stay there (spec 3.3).
    /// The last category cannot be deleted. Afterwards no state refers to `c`.
    public func delete(_ c: CategoryID) {
        guard canDeleteCategory, session.categories.contains(where: { $0.id == c }) else { return }
        perform { [classify, images, prompts] categories, states in
            var affected: [MediaID] = []
            for (id, state) in states {
                switch state {
                case .manual(c): affected.append(id)
                case .auto(let a) where a.categoryID == c: affected.append(id)
                case .heldNotSure(let a) where a.categoryID == c: affected.append(id)
                case .auto(let a): states[id] = .auto(Self.remap(a, from: c, into: nil))
                case .heldNotSure(let a): states[id] = .heldNotSure(Self.remap(a, from: c, into: nil))
                default: break
                }
            }
            let isAffected = Set(affected)
            categories.removeAll { $0.id == c }
            Self.renumber(&categories)

            // Score only the affected photos. Examples of other categories join as fixed states.
            var subset: [MediaID: Vector] = [:]
            var fixed: [MediaID: PhotoState] = [:]
            for category in categories {
                for e in category.exampleIDs where !isAffected.contains(e) {
                    subset[e] = images[e]
                    fixed[e] = .dontMove
                }
            }
            for id in affected { subset[id] = images[id] }
            let fresh = classify.classify(states: fixed, categories: categories, images: subset, prompts: prompts)

            // A photo without a vector gets the first remaining category as a placeholder guess.
            let fallback = Assignment(
                categoryID: categories[0].id, score: 0, secondCategoryID: nil, secondScore: nil, percent: 0,
                uncertain: true)
            for id in affected {
                if case .auto(let a)? = fresh[id] {
                    states[id] = .heldNotSure(a)
                } else {
                    states[id] = .heldNotSure(fallback)
                }
            }
        }
    }

    // MARK: - Suggestions

    /// Suggested categories for the "Not sure" photos (spec 3.7, 4.8), named from **All topics**, also for
    /// a session that saved an old list. Trashed photos are never in a suggestion. The clustering runs off
    /// the main actor.
    public func suggestCategories() async throws -> [CategorySuggestion] {
        let trashed = session.trashedIDs
        var notSure: [MediaID: Vector] = [:]
        for (id, state) in session.states where state.isNotSure && !trashed.contains(id) {
            if let v = images[id] { notSure[id] = v }
        }
        guard notSure.count >= SuggestionService.minimumPhotos else { return [] }
        let list = try candidates.load(ScanService.candidateList)
        let candidateVectors = try await embeddings.candidateVectors(list)
        let existingNames = Set(session.categories.map(\.displayName))
        return await Task.detached(priority: .userInitiated) {
            SuggestionService().suggest(
                notSure: notSure, candidates: list, candidateVectors: candidateVectors,
                existingNames: existingNames, seed: ScanService.seed)
        }.value
    }

    /// **Add <N> Categories** (spec 3.7): 1 undo step. Creates 1 category for each suggestion, at the end
    /// of the order and in the given order, then moves its photos into it as manual picks and examples.
    /// A suggestion with no prompts (a "Group <n>") gets the prompt "a photo of <name>" (spec 4.8).
    /// Only photos that are still "Not sure" and not trashed now are moved: a photo that the user moved,
    /// marked Don't Move, or trashed since the suggestion keeps its state (spec 4.7). A photo in 2
    /// suggestions goes to the first. A suggestion with no photo left makes no category.
    /// Returns the ids of the new categories.
    @discardableResult
    public func addSuggested(_ s: [CategorySuggestion]) -> [CategoryID] {
        let trashed = session.trashedIDs
        var claimed = Set<MediaID>()
        let added: [(id: CategoryID, suggestion: CategorySuggestion, prompts: [String], ids: [MediaID])] =
            s.compactMap { suggestion in
                let ids = suggestion.ids.filter { id in
                    session.states[id]?.isNotSure == true && !trashed.contains(id) && claimed.insert(id).inserted
                }
                guard !ids.isEmpty else { return nil }
                let prompts = suggestion.prompts.isEmpty ? ["a photo of \(suggestion.name)"] : suggestion.prompts
                return (CategoryID(), suggestion, prompts, ids)
            }
        guard !added.isEmpty else { return [] }
        var taken = session.categories
        let folderOf: [CategoryID: String] = Dictionary(uniqueKeysWithValues: added.map { item in
            let folder = SortPlanner.uniqueFolderName(for: item.suggestion.name, among: taken)
            taken.append(Category(id: item.id, displayName: item.suggestion.name, emoji: "", prompts: [], exampleIDs: [],
                                  order: taken.count, folderName: folder))
            return (item.id, folder)
        })
        let picks: [(MediaID, CategoryID)] = added.flatMap { item in item.ids.map { ($0, item.id) } }
        let embeddings = embeddings
        perform(prepare: { [weak self] in
            for item in added {
                guard let vectors = try? await embeddings.textEmbeddings(item.prompts) else { continue }
                self?.prompts[item.id] = vectors
            }
        }) { categories, states in
            var order = (categories.map(\.order).max() ?? -1) + 1
            for item in added {
                categories.append(Category(
                    id: item.id, displayName: item.suggestion.name, emoji: item.suggestion.emoji,
                    prompts: item.prompts, exampleIDs: [], order: order, folderName: folderOf[item.id]))
                order += 1
            }
            Self.pick(picks, categories: &categories, states: &states)
        }
        makeFolders(Array(folderOf.values))
        return added.map(\.id)
    }

    /// Makes the folders of new categories off the main actor. A folder that cannot be made is not an
    /// error: Done makes it when it moves the photos.
    private func makeFolders(_ names: [String]) {
        movingFiles += 1
        let folders = folders, source = source
        Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                for name in names { try? folders.ensure(name, in: source) }
            }.value
            self?.movingFiles -= 1
        }
    }

    // MARK: - Duplicates

    /// The duplicate groups of the photos that are not trashed, not unreadable, and not videos
    /// (spec 3.6, 4.9). A photo whose pixel size cannot be read (for example a missing file) is left out.
    /// Hashing reports (done, total) to `progress`. The file reads and the search run off the main actor.
    /// Groups marked **Not Duplicates** are left out.
    public func findDuplicates(
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> [DuplicateGroup] {
        let media = session.readableImages
        var vectors: [MediaID: Vector] = [:]
        var dates: [MediaID: Date] = [:]
        for m in media {
            vectors[m.id] = images[m.id]
            dates[m.id] = session.scan.dates[m.id]?.date ?? m.modified
        }
        let dismissed = session.notDuplicateKeys
        let similarity = classify.settings.duplicateSimilarity
        let source = source, imageFiles = imageFiles

        let fileHashes = try await hashes.hashes(for: media, source: source, progress: progress)
        let (found, sizes) = try await Task.detached(priority: .userInitiated) {
            var sizes: [MediaID: PixelSize] = [:]
            for m in media {
                try Task.checkCancellation()
                let url = source.appending(path: m.relativePath, directoryHint: .notDirectory)
                if let size = imageFiles.pixelSize(for: url) { sizes[m.id] = PixelSize(width: size.width, height: size.height) }
            }
            let pixels = sizes.mapValues { $0.width * $0.height }
            let groups = DuplicateService().groups(
                media: media.filter { pixels[$0.id] != nil }, hashes: fileHashes, vectors: vectors, pixels: pixels, dates: dates,
                similarity: similarity, dismissed: dismissed)
            return (groups, sizes)
        }.value
        pixelSizes = sizes

        // Photos trashed during the search leave their groups.
        let trashed = session.trashedIDs
        guard !trashed.isEmpty else {
            lastDuplicates = found
            return found
        }
        lastDuplicates = found.compactMap { g in
            var g = g
            g.ids.removeAll { trashed.contains($0) }
            g.keepIDs.subtract(trashed)
            guard g.ids.count > 1 else { return nil }
            if g.keepIDs.isEmpty { g.keepIDs = [g.ids[0]] }
            return g
        }
        return lastDuplicates
    }

    /// The pixel size of `id` that the last `findDuplicates` read, or nil (spec 3.6: each tile shows it).
    public func pixelSize(of id: MediaID) -> PixelSize? { pixelSizes[id] }

    /// **Not Duplicates** (spec 3.6): hides the group and saves its key in the session. A rescan that
    /// changes the group shows it again.
    public func dismissDuplicates(_ g: DuplicateGroup) {
        guard session.notDuplicateKeys.insert(g.id).inserted else { return }
        save()
    }

    /// **Move <N> to Trash** and **Clean Up All** (spec 3.6): moves the photos of `groups` that are not
    /// Keep photos to the Trash, as 1 undo step, through `moveToTrash`. Returns 1 `cannotTrash` error for
    /// each photo that did not move.
    ///
    /// Only the groups of the last `findDuplicates` count: a group whose photos are not all in 1 found
    /// group of the same kind is ignored. A group can have fewer photos than the found group (photos
    /// trashed since), and other Keep photos (the user changed them).
    ///
    /// `exactKeeps` are the current Keep photos of all found exact groups (the user can move the Keep of
    /// an exact group to another copy). Nil means the Keep photos that `findDuplicates` chose. They are
    /// checked: only ids of found exact groups count, and a found exact group with an available photo but
    /// none of them in `exactKeeps` keeps its original Keep photo.
    ///
    /// The groups can be stale, so each group is checked against the session now:
    /// - Photos that are trashed, moving to the Trash now, or not in the session leave the group.
    /// - A group with no Keep photo left is ignored.
    /// - No group trashes a photo of the checked `exactKeeps` or a Keep photo of any given group (spec 14).
    ///   The user can still trash such a photo with `moveToTrash`.
    /// - In an exact group, the Keep photo and each photo to trash are hashed again without the cache.
    ///   A photo whose hash is not the hash of the Keep photo any more stays.
    /// - A similar group whose Keep files are all gone from the disk trashes nothing (final review I3).
    /// - After the hashes and the disk check, the groups and the protected photos are checked again
    ///   against the session of now (final review I2).
    @discardableResult
    public func cleanUp(_ groups: [DuplicateGroup], exactKeeps: Set<MediaID>? = nil) async -> [TrashError] {
        movingFiles += 1
        defer { movingFiles -= 1 }
        let found = lastDuplicates.map { (kind: $0.kind, ids: Set($0.ids)) }
        let groups = groups.filter { g in found.contains { $0.kind == g.kind && $0.ids.isSuperset(of: g.ids) } }
        var plans = groups.compactMap {
            Self.duplicatePlan($0, protected: protection(groups, exactKeeps), available: availableIDs())
        }
        guard !plans.isEmpty else { return [] }
        let media = Dictionary(session.scan.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Exact groups: hash the Keep photo and each photo to trash again, without the cache.
        let exactFiles = plans.filter { $0.kind == .exact }.flatMap { [$0.keep] + $0.trash }.uniqued()
        let fresh = exactFiles.isEmpty
            ? [:] : await hashes.freshHashes(for: exactFiles.compactMap { media[$0] }, source: source)
        // Similar groups: find the Keep photos whose files are still on the disk.
        let similarKeeps = plans.filter { $0.kind == .similar }.flatMap(\.keeps).uniqued()
            .compactMap { id in media[id].map { (id: id, url: originalURL(of: $0)) } }
        let trash = trash
        let onDisk = similarKeeps.isEmpty
            ? [] : await Task.detached(priority: .userInitiated) { trash.existing(similarKeeps) }.value

        // The session can change during the awaits: check the groups again, with the protected photos of now.
        let protected = protection(groups, exactKeeps)
        let available = availableIDs()
        plans = plans.compactMap { plan in
            let keeps: [MediaID], trash: [MediaID]
            switch plan.kind {
            case .exact:
                guard let keepHash = fresh[plan.keep] else { return nil }
                keeps = [plan.keep]
                trash = plan.trash.filter { fresh[$0] == keepHash }
            case .similar:
                keeps = plan.keeps.filter(onDisk.contains)
                trash = plan.trash
            }
            return Self.duplicatePlan(
                DuplicateGroup(kind: plan.kind, ids: keeps + trash, keepIDs: Set(keeps)),
                protected: protected, available: available)
        }

        let ids = plans.flatMap(\.trash)
        guard !ids.isEmpty else { return [] }
        return await moveToTrash(ids)
    }

    /// The photos that no clean-up of `groups` trashes: the checked `exactKeeps` and the Keep photos of
    /// every group.
    private func protection(_ groups: [DuplicateGroup], _ exactKeeps: Set<MediaID>?) -> Set<MediaID> {
        groups.reduce(into: checkedExactKeeps(exactKeeps)) { $0.formUnion($1.keepIDs) }
    }

    /// The Keep photos of the found exact groups that clean-up protects: for each group with an available
    /// photo, its available photos in `chosen`, or else its original Keep photos.
    private func checkedExactKeeps(_ chosen: Set<MediaID>?) -> Set<MediaID> {
        let available = availableIDs()
        return lastDuplicates.filter { $0.kind == .exact }.reduce(into: []) { result, g in
            let present = Set(g.ids).intersection(available)
            guard !present.isEmpty else { return }
            let picked = chosen.map { present.intersection($0) } ?? []
            result.formUnion(picked.isEmpty ? g.keepIDs : picked)
        }
    }

    /// The photos in the session that are not trashed and not moving to the Trash now.
    private func availableIDs() -> Set<MediaID> {
        Set(session.visibleMedia.map(\.id)).subtracting(trashing)
    }

    /// What clean-up does with 1 group: its Keep photos that are `available` (`keep` is the first), and
    /// the photos to trash (available, not protected). Nil when no Keep photo of the group is available.
    private static func duplicatePlan(
        _ g: DuplicateGroup, protected: Set<MediaID>, available: Set<MediaID>
    ) -> (kind: DuplicateGroup.Kind, keep: MediaID, keeps: [MediaID], trash: [MediaID])? {
        let present = g.ids.filter(available.contains)
        let keeps = present.filter(g.keepIDs.contains)
        guard let keep = keeps.first else { return nil }
        return (g.kind, keep, keeps, present.filter { !protected.contains($0) })
    }

    // MARK: - Undo

    /// Undoes the last step. For a Move to Trash step, the photos come back from the Trash on a
    /// background task (wait with `settled()`); a photo that cannot come back stays trashed and is in
    /// `lastUndoErrors`. Does nothing while a Trash move runs.
    public func undo() {
        lastUndoErrors = []
        guard fileOperations == 0, let change = undoStack.popLast() else { return }
        guard change.trashedIDs.isEmpty else {
            runFileTask { await $0.putBack(change) }
            return
        }
        redoStack.append(snapshot())
        restore(change)
    }

    /// Does the last undone step again. A Move to Trash step trashes the photos again, with the rules of
    /// `moveToTrash`; a photo that cannot move is in `lastUndoErrors`. Does nothing while a Trash move runs.
    public func redo() {
        lastUndoErrors = []
        guard fileOperations == 0, let change = redoStack.popLast() else { return }
        guard change.trashedIDs.isEmpty else {
            runFileTask { $0.lastUndoErrors = await $0.trashFiles(change.trashedIDs, newAction: false) }
            return
        }
        undoStack.append(snapshot())
        restore(change)
    }

    // MARK: - Views

    /// Not-sure photos grouped by best category, largest group first, ties by category order (spec 3.4).
    public var notSureGroups: [(category: CategoryID, ids: [MediaID])] {
        var groups: [CategoryID: [MediaID]] = [:]
        for (id, state) in session.states where state.isNotSure {
            if let a = Self.assignment(state) { groups[a.categoryID, default: []].append(id) }
        }
        let order = Dictionary(uniqueKeysWithValues: session.categories.map { ($0.id, $0.order) })
        return groups
            .map { (category: $0.key, ids: $0.value.sorted()) }
            .sorted { lhs, rhs in
                if lhs.ids.count != rhs.ids.count { return lhs.ids.count > rhs.ids.count }
                let l = order[lhs.category] ?? .max, r = order[rhs.category] ?? .max
                return l != r ? l < r : lhs.category.uuidString < rhs.category.uuidString
            }
    }

    /// True when many photos are "Not sure": `SuggestionService.manyNotSure` over the images that are
    /// not trashed (videos do not count).
    public var hasManyNotSure: Bool {
        let counts = session.notSureImageCounts
        return SuggestionService.manyNotSure(notSure: counts.notSure, images: counts.images)
    }

    /// Sidebar counts (spec 3.3). `perCategory` counts manual picks and certain auto photos.
    public func counts() -> (
        all: Int, notSure: Int, changedByYou: Int, perCategory: [CategoryID: Int], dontMove: Int, videos: Int,
        unreadable: Int
    ) {
        var perCategory = Dictionary(uniqueKeysWithValues: session.categories.map { ($0.id, 0) })
        var notSure = 0, manual = 0, dontMove = 0, unreadable = 0
        for state in session.states.values {
            if state.isNotSure { notSure += 1 }
            switch state {
            case .manual(let c):
                manual += 1
                perCategory[c, default: 0] += 1
            case .auto(let a) where !a.uncertain:
                perCategory[a.categoryID, default: 0] += 1
            case .dontMove: dontMove += 1
            case .unreadable: unreadable += 1
            default: break
            }
        }
        // Trashed photos have no state, so only `all` and `videos` must leave them out.
        let media = session.visibleMedia
        let videos = media.filter { $0.kind == .video }.count
        return (media.count, notSure, manual, perCategory, dontMove, videos, unreadable)
    }

    // MARK: - Steps

    private func known(_ ids: [MediaID]) -> [MediaID] {
        ids.filter { session.states[$0] != nil }.uniqued()
    }

    private func editCategory(_ c: CategoryID, _ edit: @escaping (inout Category) -> Void) {
        guard session.categories.contains(where: { $0.id == c }) else { return }
        perform { categories, _ in
            if let i = categories.firstIndex(where: { $0.id == c }) { edit(&categories[i]) }
        }
    }

    /// Applies a change at once. If something changed, pushes an undo snapshot, clears redo,
    /// then starts the background recalculation.
    private func perform(
        prepare: (@MainActor @Sendable () async -> Void)? = nil,
        _ change: (inout [Category], inout [MediaID: PhotoState]) -> Void
    ) {
        var categories = session.categories
        var states = session.states
        change(&categories, &states)
        guard categories != session.categories || states != session.states else { return }
        pushUndo(snapshot(), newAction: true)
        session.categories = categories
        session.states = states
        updateFlags()
        recalculate(prepare: prepare)
    }

    /// Pushes an undo step. A new action (not a redo) also clears the redo stack.
    private func pushUndo(_ change: ReviewChange, newAction: Bool) {
        undoStack.append(change)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        if newAction {
            redoStack.removeAll()
            redoEpoch += 1
        }
    }

    /// Restores a snapshot. Trashed photos stay trashed: they get no state and no example place back,
    /// even if the snapshot is from before they were trashed. A photo the snapshot does not know (it
    /// was trashed then, and could not be trashed again by a redo) keeps its state and example places.
    private func restore(_ change: ReviewChange) {
        var categories = change.categories, states = change.states
        let trashed = session.trashedIDs
        let unknown = Set(session.states.keys.filter { states[$0] == nil && !trashed.contains($0) })
        if !unknown.isEmpty {
            for id in unknown { states[id] = session.states[id] }
            Self.addExamples(of: unknown, from: session.categories, to: &categories)
        }
        Self.strip(trashed, categories: &categories, states: &states)
        session.categories = categories
        session.states = states
        updateFlags()
        recalculate()
    }

    private func snapshot() -> ReviewChange {
        ReviewChange(categories: session.categories, states: session.states)
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty && fileOperations == 0
        canRedo = !redoStack.isEmpty && fileOperations == 0
    }

    // MARK: - Trash steps

    /// Runs an undo or redo that moves files, as `fileTask`. Undo and redo stay off until it ends.
    private func runFileTask(_ work: @escaping @MainActor (ReviewService) async -> Void) {
        fileOperations += 1
        movingFiles += 1
        updateFlags()
        let previous = fileTask
        fileTask = Task {
            await previous?.value
            await work(self)
            self.fileOperations -= 1
            self.movingFiles -= 1
            self.updateFlags()
        }
    }

    /// Moves the files of `ids` to the Trash off the main actor, then records the photos that moved as
    /// 1 undo step. `newAction` is false for a redo, which keeps the redo stack.
    private func trashFiles(_ ids: [MediaID], newAction: Bool) async -> [TrashError] {
        movingFiles += 1
        defer { movingFiles -= 1 }
        let trashed = session.trashedIDs
        let media = Dictionary(session.scan.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items: [(id: MediaID, url: URL)] = ids.uniqued().compactMap { id in
            guard !trashed.contains(id), !trashing.contains(id), let m = media[id] else { return nil }
            return (id, originalURL(of: m))
        }
        guard !items.isEmpty else { return [] }

        let moving = Set(items.map(\.id))
        trashing.formUnion(moving)
        fileOperations += 1
        updateFlags()
        let trash = trash
        let result = await Task.detached(priority: .userInitiated) { trash.trash(items) }.value
        fileOperations -= 1
        trashing.subtract(moving)

        // The files are in the Trash now, so record them even if the session changed meanwhile.
        let done = result.done.filter { !session.trashedIDs.contains($0.mediaID) }
        if !done.isEmpty {
            let moved = done.map(\.mediaID)
            var change = snapshot()
            change.trashedIDs = moved
            pushUndo(change, newAction: newAction)
            session.trashed += done
            var categories = session.categories, states = session.states
            Self.strip(Set(moved), categories: &categories, states: &states)
            session.categories = categories
            session.states = states
            save()  // Record the trashed files at once, before the recalculation.
            recalculate()
        }
        updateFlags()
        return result.failed
    }

    /// Undo of a Move to Trash step: puts each photo back off the main actor. A photo that comes back
    /// gets its state and example places of `change` (the state before the trash). A photo that cannot
    /// come back stays trashed and is reported in `lastUndoErrors`.
    private func putBack(_ change: ReviewChange) async {
        let media = Dictionary(session.scan.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var errors: [TrashError] = []
        var items: [(record: TrashedPhoto, original: URL)] = []
        for id in change.trashedIDs {
            guard let record = session.trashed.first(where: { $0.mediaID == id }) else { continue }
            guard let m = media[id] else {
                errors.append(.cannotPutBack(id, "the photo is not in the session any more"))
                continue
            }
            items.append((record, originalURL(of: m)))
        }
        let epoch = redoEpoch
        let trash = trash
        let results = await Task.detached(priority: .userInitiated) {
            items.map { trash.putBack($0.record, to: $0.original) }
        }.value

        var back: Set<MediaID> = []
        for (item, error) in zip(items, results) {
            if let error { errors.append(error) } else { back.insert(item.record.mediaID) }
        }
        lastUndoErrors = errors
        guard !back.isEmpty else { return }

        let redo = ReviewChange(
            categories: session.categories, states: session.states, trashedIDs: change.trashedIDs.filter(back.contains))
        session.trashed.removeAll { back.contains($0.mediaID) }
        let categoryIDs = Set(session.categories.map(\.id))
        for id in back {
            // A state that points to a category that is gone is dropped; the photo is classified again.
            session.states[id] = change.states[id].flatMap { Self.refersOnly(to: categoryIDs, $0) ? $0 : nil }
        }
        Self.addExamples(of: back, from: change.categories, to: &session.categories)
        // A new action during the put back cleared the redo stack. Then this undo cannot be redone.
        if epoch == redoEpoch { redoStack.append(redo) }
        updateFlags()
        save()
        recalculate()
    }

    private func originalURL(of m: MediaFile) -> URL {
        source.appending(path: m.relativePath, directoryHint: .notDirectory)
    }

    /// Runs after the previous recalculation, so prompt vectors of new categories are ready.
    /// The result is applied and saved only if no newer change happened.
    private func recalculate(prepare: (@MainActor @Sendable () async -> Void)? = nil) {
        generation += 1
        let current = generation
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            if let prepare { await prepare() }
            guard let self, self.generation == current else { return }
            let classify = self.classify
            let states = self.session.states, categories = self.session.categories
            let prompts = self.prompts
            // Trashed photos keep their vectors for undo, but are not classified.
            let trashed = self.session.trashedIDs
            let images = trashed.isEmpty ? self.images : self.images.filter { !trashed.contains($0.key) }
            let result = await Task.detached(priority: .userInitiated) {
                classify.classify(states: states, categories: categories, images: images, prompts: prompts)
            }.value
            guard self.generation == current else { return }
            self.session.states = result
            self.save()
        }
    }

    private func save() {
        guard !isClosed else {
            unsavedWhileClosed = true
            return
        }
        unsavedWhileClosed = false
        do {
            try sessions.save(session)
            saveError = nil
        } catch {
            saveError = error
        }
    }

    private static func assignment(_ state: PhotoState) -> Assignment? {
        switch state {
        case .auto(let a), .heldNotSure(let a): a
        default: nil
        }
    }

    /// Manual picks: each photo goes to its category and is an example of that category only.
    private static func pick(
        _ picks: [(MediaID, CategoryID)], categories: inout [Category], states: inout [MediaID: PhotoState]
    ) {
        var target: [MediaID: CategoryID] = [:]
        for (id, c) in picks {
            states[id] = .manual(c)
            target[id] = c
        }
        for i in categories.indices {
            let c = categories[i].id
            categories[i].exampleIDs.removeAll { target[$0] != nil && target[$0] != c }
            let present = Set(categories[i].exampleIDs)
            categories[i].exampleIDs += picks.filter { $0.1 == c && !present.contains($0.0) }.map(\.0).uniqued()
        }
    }

    /// Removes photos from `states` and from every `exampleIDs`.
    private static func strip(_ ids: Set<MediaID>, categories: inout [Category], states: inout [MediaID: PhotoState]) {
        guard !ids.isEmpty else { return }
        for id in ids { states[id] = nil }
        for i in categories.indices { categories[i].exampleIDs.removeAll { ids.contains($0) } }
    }

    /// Adds `ids` as examples of each category in `categories` that had them as examples in `source`.
    private static func addExamples(of ids: Set<MediaID>, from source: [Category], to categories: inout [Category]) {
        let had = Dictionary(source.map { ($0.id, $0.exampleIDs.filter(ids.contains)) }, uniquingKeysWith: { first, _ in first })
        for i in categories.indices {
            guard let add = had[categories[i].id], !add.isEmpty else { continue }
            let present = Set(categories[i].exampleIDs)
            categories[i].exampleIDs += add.filter { !present.contains($0) }
        }
    }

    /// True if every category the state names is in `ids`.
    private static func refersOnly(to ids: Set<CategoryID>, _ state: PhotoState) -> Bool {
        switch state {
        case .manual(let c): ids.contains(c)
        case .auto(let a), .heldNotSure(let a):
            ids.contains(a.categoryID) && (a.secondCategoryID.map(ids.contains) ?? true)
        case .dontMove, .unreadable: true
        }
    }

    /// Points references to `from` at `into`. With `into` nil, a second guess of `from` is cleared.
    private static func remap(_ a: Assignment, from: CategoryID, into: CategoryID?) -> Assignment {
        var a = a
        if a.categoryID == from, let into { a.categoryID = into }
        if a.secondCategoryID == from { a.secondCategoryID = into }
        if a.secondCategoryID == nil || a.secondCategoryID == a.categoryID {
            a.secondCategoryID = nil
            a.secondScore = nil
        }
        return a
    }

    private static func renumber(_ categories: inout [Category]) {
        categories.sort { $0.order < $1.order }
        for i in categories.indices { categories[i].order = i }
    }
}

extension Array where Element: Hashable {
    /// The elements in their first order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
