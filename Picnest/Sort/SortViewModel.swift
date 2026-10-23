import Foundation
import Observation
import PicnestCore
import Synchronization

/// State of the Sort sheet (spec 3.5). Talks to `ReviewService`, `SortService` and `LibraryService` only.
/// The plan is made again off the main actor after each option change; only the newest plan is kept.
@MainActor
@Observable
final class SortViewModel: Identifiable {
    enum State: Equatable {
        case editing
        /// Move mode: the confirmation dialog shows.
        case confirmingMove
        case running(done: Int, total: Int)
        case finished(copied: Int, moved: Int)
        /// The user clicked **Stop**. The journal has no `done` line.
        case stopped(done: Int, total: Int)
        case failed(String)
    }

    /// Every change makes the plan again.
    var options: SortOptions {
        didSet { if options != oldValue { replan() } }
    }
    private(set) var plan: SortPlan?
    private(set) var planError: SortPlanError?
    /// A plan failure that is not a `SortPlanError`, as user text.
    private(set) var planFailure: String?
    private(set) var state: State = .editing
    private(set) var isPlanning = false
    /// True while **Undo Last Sort** runs.
    private(set) var isUndoing = false
    /// True after **Stop** until the sort stops.
    private(set) var isStopping = false
    /// True when the journal of the last sort has no `done` line, so **Undo Last Sort** shows.
    private(set) var canUndoLastSort = false
    /// A short notice above the buttons, for example when the plan changed before **Sort** ran.
    private(set) var notice: String?
    /// The photos of the session that are still Not sure, at the last plan.
    private(set) var notSureCount = 0
    /// The non-trashed images (no videos), and how many of them are Not sure, at the last plan.
    /// The hint uses both, so numerator and denominator come from the same set.
    private(set) var imageCount = 0
    private(set) var notSureImageCount = 0

    @ObservationIgnored private let review: ReviewService
    @ObservationIgnored private let sortService: SortService
    @ObservationIgnored private let library: LibraryService
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let onDone: () -> Void
    @ObservationIgnored private let onSuggest: () -> Void
    @ObservationIgnored private let source: URL
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var stopFlag: StopFlag?

    /// `onDone` closes the session after a sort (spec 9.1). `AppModel.done` goes back to the Welcome screen.
    init(review: ReviewService, sortService: SortService, library: LibraryService, locale: Locale = .current,
         onDone: @escaping () -> Void = {}, onSuggest: @escaping () -> Void = {}) {
        self.review = review
        self.sortService = sortService
        self.library = library
        self.locale = locale
        self.onDone = onDone
        self.onSuggest = onSuggest
        source = URL(filePath: review.session.sourcePath, directoryHint: .isDirectory)
        options = .defaults(source: source)
        canUndoLastSort = sortService.hasUnfinishedSort(journal: library.journal(for: source))
    }

    /// Waits until the last review change is saved, then makes the first plan. Call it before the sheet shows.
    func load() async {
        await review.settled()
        replan()
        await planned()
    }

    /// Waits until the newest plan is made. For tests.
    func planned() async {
        while let task = planTask {
            await task.value
            if planTask == task { return }
        }
    }

    /// Waits until the running sort or undo, and the plan it started, are done. For tests.
    func finished() async {
        await runTask?.value
        await planned()
    }

    // MARK: - Texts

    var title: String {
        guard let plan else { return "Sort photos" }
        return "Sort \(count(plan.entries.count, "photo", "photos")) into \(count(plan.folderCounts.count, "folder", "folders"))"
    }

    /// The photos that stay in the source folder (Don't move, or Not sure with Leave in the source folder).
    var subtitle: String? {
        guard let left = plan?.leftInSource, left > 0 else { return nil }
        return left == 1 ? "1 photo stays in the source folder." : "\(number(left)) photos stay in the source folder."
    }

    /// The destination path with the home folder as `~`.
    var destinationText: String {
        var path = options.destination.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return ReviewViewModel.abbreviate(path, home: NSHomeDirectory())
    }

    /// The short reason under the destination row when the destination cannot be used.
    var destinationNote: String? {
        switch planError {
        case .destinationIsSource?: "The destination is the source folder. Choose another folder."
        case .destinationInsideSource?: "Choose a folder outside the source folder."
        case .categoryFolderInsideSource?: "A category folder would land inside the source folder. Choose another destination."
        case nil: planFailure
        }
    }

    /// The save error of the review, for example when `sortedAt` could not be saved after the sort (final review I4).
    var saveWarning: String? { review.saveError.map(SortMessages.saveFailed) }

    var showNotSureChoice: Bool { notSureCount > 0 }

    /// The hint to suggest categories when many images are Not sure (`SuggestionService.manyNotSure`, spec 3.5).
    var showSuggestHint: Bool { SuggestionService.manyNotSure(notSure: notSureImageCount, images: imageCount) }

    var suggestHintText: String { "\(count(notSureImageCount, "photo", "photos")) are not sure." }

    /// **Suggest Categories…**: the screen closes this sheet, shows the Not sure view and opens the suggest sheet.
    func suggestFromSort() { onSuggest() }

    var notSureHeader: String { "\(count(notSureCount, "photo", "photos")) still \"Not sure\":" }

    /// The folder tree: the destination, the first 3 folders with counts, the first file of the first
    /// folder, then `…` if more folders follow.
    var previewLines: [String] {
        guard let plan else { return [] }
        let destination = options.destination
        var lines = [destination.lastPathComponent + "/"]
        let shown = plan.folderCounts.prefix(3)
        let more = plan.folderCounts.count > shown.count
        for (i, item) in shown.enumerated() {
            let isLast = i == shown.count - 1 && !more
            lines.append("\(isLast ? "└" : "├") \(item.folder)/  \(number(item.count))")
            if i == 0, let first = Self.firstFile(in: item.folder, of: plan, destination: destination) {
                lines.append("\(isLast ? " " : "│")  └ \(first)")
            }
        }
        if more { lines.append("└ …") }
        return lines
    }

    var sortButtonTitle: String {
        guard options.mode == .move else { return "Sort" }
        let n = plan?.entries.count ?? 0
        return n == 1 ? "Move 1 Photo" : "Move \(number(n)) Photos"
    }

    /// The Move confirmation: "Move <N> photos?" with `confirmMoveMessage` under it.
    var confirmMoveTitle: String { "Move \(count(plan?.entries.count ?? 0, "photo", "photos"))?" }

    let confirmMoveMessage = SortViewModel.moveDetail

    /// The text of the Move card and of the Move confirmation (spec 3.5).
    static let moveDetail = "Each original is deleted after its copy is checked."

    var canSort: Bool {
        guard state == .editing, !isPlanning, planError == nil, let plan else { return false }
        return !plan.entries.isEmpty
    }

    /// False when no file was copied or moved, so the destination may not exist.
    var canShowInFinder: Bool {
        switch state {
        case .finished(let copied, let moved): copied + moved > 0
        case .stopped(let done, _): done > 0
        default: false
        }
    }

    static let planChangedNotice = "The photos changed. Check the new plan, then sort again."
    static let nothingToSortNotice = "Nothing to sort."

    /// True while files change. The sheet cannot close then.
    /// True while the sort or its undo runs, or while review files move to or from the Trash (final
    /// review I1). **Done** and **Undo Last Sort** are off.
    var isBusy: Bool {
        if case .running = state { return true }
        return isUndoing || review.isMovingFiles
    }

    /// 0...1 while the sort runs.
    var progress: Double {
        guard case .running(let done, let total) = state, total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    var progressText: String {
        guard case .running(let done, let total) = state else { return "" }
        return "\(options.mode == .move ? "Moving" : "Copying") \(number(done)) of \(number(total))…"
    }

    var summaryText: String {
        switch state {
        case .finished(let copied, let moved):
            let verb = moved > 0 ? "Moved" : "Copied"
            return "\(verb) \(count(copied + moved, "photo", "photos")) to “\(options.destination.lastPathComponent)”."
        case .stopped(let done, let total):
            return "Stopped after \(number(done)) of \(count(total, "photo", "photos"))."
        case .failed(let message):
            return message
        default:
            return ""
        }
    }

    // MARK: - Actions

    func setDestination(_ url: URL) {
        options.destination = url
    }

    /// Copy mode starts the sort. Move mode asks for confirmation first.
    func sort() {
        guard canSort else { return }
        if options.mode == .move {
            state = .confirmingMove
        } else {
            start()
        }
    }

    /// The **Move** button of the confirmation. The dialog can clear `.confirmingMove` before it runs the action.
    func confirmMove() {
        guard options.mode == .move, state == .confirmingMove || canSort else { return }
        start()
    }

    func cancelMove() {
        if state == .confirmingMove { state = .editing }
    }

    /// Finishes the current file, then stops. The journal keeps the files that were done.
    func stop() {
        guard let stopFlag else { return }
        stopFlag.set()
        isStopping = true
    }

    /// From a failure back to the options.
    func backToOptions() {
        guard case .failed = state else { return }
        state = .editing
        replan()
    }

    /// **Done**: the sheet closes. Only a finished sort closes the session too (spec 9.1). After a stop or
    /// a failure, the app stays in review, where **Undo Last Sort** shows if files were placed.
    func done() {
        guard !isBusy, case .finished = state else { return }
        onDone()
    }

    /// Reverses the last sort (stopped or failed), clears the sort time, then shows the options again.
    func undoLastSort() {
        guard canUndoLastSort, !isBusy else { return }
        isUndoing = true
        let library = self.library, review = self.review
        runTask = Task {
            let result: Result<Void, any Error>
            do {
                try await library.undoLastSort(review: review)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            isUndoing = false
            canUndoLastSort = sortService.hasUnfinishedSort(journal: library.journal(for: source))
            switch result {
            case .success:
                state = .editing
                replan()
            case .failure(let error):
                state = .failed(SortMessages.text(for: error))
            }
        }
    }

    // MARK: - Steps

    private func replan() {
        planTask?.cancel()
        generation += 1
        let current = generation
        let session = review.session, options = options, source = source, service = sortService
        isPlanning = true
        notice = nil
        planTask = Task {
            let result = await Self.makePlan(service, session: session, source: source, options: options)
            guard current == generation else { return }
            apply(result, session: session)
            isPlanning = false
        }
    }

    private func apply(_ result: Result<SortPlan, any Error>, session: Session) {
        notSureCount = session.states.values.filter(\.isNotSure).count
        (notSureImageCount, imageCount) = session.notSureImageCounts
        switch result {
        case .success(let p):
            plan = p
            planError = nil
            planFailure = nil
        case .failure(let error):
            plan = nil
            planError = error as? SortPlanError
            planFailure = planError == nil ? error.localizedDescription : nil
        }
    }

    private nonisolated static func makePlan(_ service: SortService, session: Session, source: URL,
                                             options: SortOptions) async -> Result<SortPlan, any Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try service.plan(session, source: source, options: options) }
        }.value
    }

    private func start() {
        // A plan that is still being made is dropped: the run makes its own plan.
        planTask?.cancel()
        planTask = nil
        generation += 1
        isPlanning = false
        notice = nil
        let flag = StopFlag()
        stopFlag = flag
        state = .running(done: 0, total: plan?.entries.count ?? 0)
        runTask = Task { await run(flag) }
    }

    private func run(_ flag: StopFlag) async {
        // Plan again from the latest saved review states.
        await review.settled()
        let session = review.session, options = options
        let shown = self.plan
        let result = await Self.makePlan(sortService, session: session, source: source, options: options)
        apply(result, session: session)
        guard case .success(let plan) = result else {
            state = .editing
            return
        }
        guard !plan.entries.isEmpty else {
            notice = Self.nothingToSortNotice
            state = .editing
            return
        }
        // Only the plan that the user saw (and, for Move, confirmed) runs.
        guard let shown, Self.samePlan(shown, plan) else {
            notice = Self.planChangedNotice
            state = .editing
            return
        }
        let journal = library.journal(for: source)
        let total = plan.entries.count
        var done = 0
        var retried = false
        state = .running(done: 0, total: total)
        attempt: while true {
            do {
                for try await event in sortService.run(plan, mode: options.mode, journal: journal, stop: { flag.isSet }) {
                    switch event {
                    case .progress(let d, let t):
                        done = d
                        state = .running(done: d, total: t)
                    case .finished(let copied, let moved):
                        recordSort(session)
                        state = .finished(copied: copied, moved: moved)
                    }
                }
                break attempt
            } catch SortError.busy where !retried {
                // Another sort or undo is finishing its current file. Wait, then try 1 more time.
                retried = true
                await sortService.waitUntilIdle()
            } catch SortError.stopped {
                if done > 0 { recordSort(session) }
                state = .stopped(done: done, total: total)
                break attempt
            } catch {
                if done > 0 { recordSort(session) }
                state = .failed(SortMessages.text(for: error))
                break attempt
            }
        }
        stopFlag = nil
        isStopping = false
        canUndoLastSort = sortService.hasUnfinishedSort(journal: journal)
    }

    /// Spec 9.1: the session and the recent folder list keep the time of the sort.
    private func recordSort(_ session: Session) {
        let now = Date.now
        review.markSorted(at: now)
        library.remember(source, photoCount: session.scan.media.count, sortedAt: now)
    }

    /// True if both plans place the same files at the same destinations, in the same order.
    private static func samePlan(_ a: SortPlan, _ b: SortPlan) -> Bool {
        a.entries.count == b.entries.count
            && zip(a.entries, b.entries).allSatisfy { $0.source == $1.source && $0.destination == $1.destination }
    }

    private static func firstFile(in folder: String, of plan: SortPlan, destination: URL) -> String? {
        let prefix = destination.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
        let base = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return plan.entries
            .map { $0.destination.path(percentEncoded: false) }
            .filter { $0.hasPrefix(base) }
            .map { String($0.dropFirst(base.count)) }
            .min()
    }

    private func number(_ n: Int) -> String {
        n.formatted(.number.locale(locale))
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(number(n)) \(many)"
    }
}

/// The **Stop** flag. The sort reads it between files, off the main actor.
private final class StopFlag: Sendable {
    private let value = Atomic<Bool>(false)

    var isSet: Bool { value.load(ordering: .relaxed) }

    func set() { value.store(true, ordering: .relaxed) }
}
