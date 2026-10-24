import Foundation
import Synchronization

public enum SortError: Error, Equatable {
    /// These files changed or were removed after the scan. Nothing was done. Rescan first.
    case changedSinceScan([MediaID])
    /// These destination files exist. Nothing was done (or, if found during the sort, the sort stopped).
    case destinationExists([URL])
    /// The journal of the last sort has no `done` line. Undo the last sort first.
    case unfinishedLastSort
    /// The copy has a different size from the source. The bad copy was removed and the source kept.
    case sizeMismatch(URL)
    /// The user stopped the sort. No `done` line was written.
    case stopped
    /// Undo finished, but did not touch these destination files (see `SortService.undo`).
    case undoConflicts([URL])
    /// No journal exists.
    case nothingToUndo
    /// Another sort or undo of this service is still running (see `SortService.waitUntilIdle`).
    case busy
    /// The folder moved after a sort that did not finish. The journal holds the old paths, so Undo works
    /// only after the user moves the folder back to `oldPath` (final review I3).
    case movedAfterUnfinishedSort(oldPath: String)
}

public enum SortEvent: Sendable {
    case progress(done: Int, total: Int)
    case finished(copied: Int, moved: Int)
}

/// Runs a sort plan with a journal, and undoes the last sort (spec 7.3).
/// 1 service runs 1 operation at a time: a `run` or `undo` while another one is active throws `.busy`.
/// Use 1 service for the app.
public final class SortService: Sendable {
    private struct Activity {
        var active = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let fileOps: any FileOps
    private let activity = Mutex(Activity())

    public init(fileOps: any FileOps = LocalFileOps()) {
        self.fileOps = fileOps
    }

    /// The sort plan, with the names that exist in the destination folders today.
    public func plan(_ session: Session, source: URL, options: SortOptions) throws -> SortPlan {
        try SortPlanner().plan(session, source: source, options: options, existingNames: { self.fileOps.names(in: $0) })
    }

    /// The in-place plan, with the names that exist in the target folders today.
    public func planInPlace(_ session: Session, source: URL, rename: Bool = true) throws -> SortPlan {
        try SortPlanner().planInPlace(
            session, source: source, rename: rename, existingNames: { self.fileOps.names(in: $0) })
    }

    /// Moves the files of an in-place plan into the source folder's sub-folders (spec 7.2). Within one
    /// volume this is a rename, so each move is atomic and never overwrites. There is no journal: an
    /// organize cannot be undone. Throws `.busy`, `.changedSinceScan`, or `.destinationExists` before
    /// any move. A file that cannot move is reported in `failures`; the other files still go on.
    public func organize(
        _ plan: SortPlan, source: URL, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) throws -> OrganizeResult {
        guard begin() else { throw SortError.busy }
        defer { end() }
        try precheck(plan)
        let total = plan.entries.count
        var moves: [OrganizeMove] = []
        var failures: [OrganizeFailure] = []
        for (i, entry) in plan.entries.enumerated() {
            do {
                try makeFolders(entry.destination.deletingLastPathComponent())
                try fileOps.move(entry.source, entry.destination)
                moves.append(OrganizeMove(
                    mediaID: entry.mediaID, to: Self.relativePath(of: entry.destination, in: source)))
            } catch {
                failures.append(OrganizeFailure(mediaID: entry.mediaID, message: error.localizedDescription))
            }
            progress(i + 1, total)
        }
        return OrganizeResult(moves: moves, failures: failures)
    }

    /// Emits `.progress` after each file and `.finished` after the `done` line is written.
    /// `stop` is checked between files; cancelling the consumer works the same as Stop.
    public func run(_ plan: SortPlan, mode: SortMode, journal: JournalRepository,
                    stop: @escaping @Sendable () -> Bool) -> AsyncThrowingStream<SortEvent, Error> {
        AsyncThrowingStream { continuation in
            guard self.begin() else {
                continuation.finish(throwing: SortError.busy)
                return
            }
            let task = Task.detached(priority: .userInitiated) {
                // Active until the producer stops, also after a cancel (it finishes the current file).
                defer { self.end() }
                do {
                    let (copied, moved) = try self.perform(plan, mode: mode, journal: journal, stop: stop) {
                        continuation.yield($0)
                    }
                    continuation.yield(.finished(copied: copied, moved: moved))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reverses the journal from the last entry to the first, then archives it as `<timestamp>.undone`.
    ///
    /// - `copy`: removes the destination, but only if the source still exists (else it is the only copy).
    /// - `move`: copies the destination back to the source, checks the size, then removes the destination.
    ///   If a file exists at the source path, nothing is overwritten and the destination is kept.
    /// - `mkdir`: removes the folder if it is empty.
    ///
    /// Files that were kept are reported with `.undoConflicts` after all other work is done.
    /// If a file operation fails, it throws at once and keeps the journal, so Undo can run again.
    public func undo(journal: JournalRepository) throws {
        guard begin() else { throw SortError.busy }
        defer { end() }
        guard try journal.lastIsComplete() != nil else { throw SortError.nothingToUndo }
        var conflicts: [URL] = []
        for entry in try journal.read().reversed() {
            switch entry.op {
            case .done:
                continue
            case .mkdir:
                guard let path = entry.destination else { continue }
                let folder = URL(filePath: path, directoryHint: .isDirectory)
                if fileOps.isEmptyFolder(folder) { try fileOps.removeEmptyFolder(folder) }
            case .copy:
                guard let (src, dst) = Self.pair(entry), fileOps.exists(dst) else { continue }
                if fileOps.exists(src) {
                    try fileOps.remove(dst)
                } else {
                    conflicts.append(dst)
                }
            case .move:
                guard let (src, dst) = Self.pair(entry) else { continue }
                if try !restore(src: src, dst: dst) { conflicts.append(dst) }
            }
        }
        try journal.archive(suffix: Self.timestamp() + ".undone")
        if !conflicts.isEmpty { throw SortError.undoConflicts(conflicts) }
    }

    /// True if the journal of the last sort has no `done` line (a stopped or failed sort), so
    /// **Undo Last Sort** is needed before a new sort. An unreadable journal also counts as unfinished.
    public func hasUnfinishedSort(journal: JournalRepository) -> Bool {
        do {
            return try journal.lastIsComplete() == false
        } catch {
            return true
        }
    }

    /// True while a `run` or `undo` changes files. The app does not quit then (final review M4).
    public var isRunning: Bool {
        activity.withLock { $0.active }
    }

    /// Returns when no `run` or `undo` is active, for example after a cancelled sort finished its current file.
    public func waitUntilIdle() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = activity.withLock { a -> Bool in
                if !a.active { return true }
                a.waiters.append(c)
                return false
            }
            if resumeNow { c.resume() }
        }
    }

    private func begin() -> Bool {
        activity.withLock { a in
            if a.active { return false }
            a.active = true
            return true
        }
    }

    private func end() {
        let waiters = activity.withLock { a in
            a.active = false
            defer { a.waiters = [] }
            return a.waiters
        }
        for w in waiters { w.resume() }
    }

    // MARK: - Sort

    private func perform(_ plan: SortPlan, mode: SortMode, journal: JournalRepository, stop: () -> Bool,
                         progress: (SortEvent) -> Void) throws -> (copied: Int, moved: Int) {
        let complete = try journal.lastIsComplete()
        if complete == false { throw SortError.unfinishedLastSort }
        try precheck(plan)
        if complete == true { try journal.archive(suffix: Self.timestamp()) }

        let total = plan.entries.count
        var copied = 0
        var moved = 0
        for (i, entry) in plan.entries.enumerated() {
            if stop() || Task.isCancelled { throw SortError.stopped }
            try place(entry, mode: mode, journal: journal)
            if mode == .move { moved += 1 } else { copied += 1 }
            progress(.progress(done: i + 1, total: total))
        }
        try journal.append(JournalEntry(op: .done, source: nil, destination: nil, time: .now))
        return (copied, moved)
    }

    /// Spec 7.3 steps 1–2: runs before any file operation.
    private func precheck(_ plan: SortPlan) throws {
        var changed: [MediaID] = []
        var existing: [URL] = []
        for e in plan.entries {
            let same = fileOps.exists(e.source)
                && (try? fileOps.size(e.source)) == e.size
                && (try? fileOps.modified(e.source)) == e.modified
            if !same { changed.append(e.mediaID) }
            if fileOps.exists(e.destination) { existing.append(e.destination) }
        }
        if !changed.isEmpty { throw SortError.changedSinceScan(changed) }
        if !existing.isEmpty { throw SortError.destinationExists(existing) }
    }

    /// Copies (or moves) 1 file. The journal entry is written only after the work is done.
    private func place(_ e: PlanEntry, mode: SortMode, journal: JournalRepository) throws {
        try makeFolders(e.destination.deletingLastPathComponent()) {
            try journal.append(JournalEntry(op: .mkdir, source: nil, destination: $0.path, time: .now))
        }
        // A file that appeared during the sort is never touched.
        if fileOps.exists(e.destination) { throw SortError.destinationExists([e.destination]) }
        try copyRemovingPartial(e.source, e.destination)

        guard mode == .move else {
            try journal.append(Self.entry(.copy, e.source, e.destination))
            return
        }
        // From here, the destination is our own complete copy, so it is safe to remove it.
        let copySize: Int64
        do {
            copySize = try fileOps.size(e.destination)
        } catch {
            try? fileOps.remove(e.destination)
            throw error
        }
        guard copySize == e.size else {
            do {
                try fileOps.remove(e.destination)
            } catch {
                // Let Undo remove the bad copy.
                try? journal.append(Self.entry(.copy, e.source, e.destination))
            }
            throw SortError.sizeMismatch(e.destination)
        }
        do {
            try fileOps.remove(e.source)
        } catch {
            // Both files exist: record a copy, so Undo removes the destination and keeps the source.
            try journal.append(Self.entry(.copy, e.source, e.destination))
            throw error
        }
        try journal.append(Self.entry(.move, e.source, e.destination))
    }

    /// Makes the missing folders, 1 level at a time from the top, and calls `made` after each one.
    private func makeFolders(_ folder: URL, made: (URL) throws -> Void = { _ in }) throws {
        var missing: [URL] = []
        var f = folder.standardizedFileURL
        while !fileOps.exists(f) {
            missing.append(f)
            let parent = f.deletingLastPathComponent()
            if parent.path == f.path { break }
            f = parent
        }
        for m in missing.reversed() {
            try fileOps.makeFolder(m)
            try made(m)
        }
    }

    // MARK: - Undo

    /// Puts a moved file back. Returns false if the destination was kept (a conflict).
    private func restore(src: URL, dst: URL) throws -> Bool {
        if fileOps.exists(src) {
            // Already put back by an earlier Undo, or a new file is there: never overwrite it.
            return !fileOps.exists(dst)
        }
        guard fileOps.exists(dst) else { return false }  // The file is gone from both places.
        try makeFolders(src.deletingLastPathComponent())
        try copyRemovingPartial(dst, src)
        // From here, `src` is our own copy (it did not exist before the copy).
        guard try fileOps.size(src) == fileOps.size(dst) else {
            try fileOps.remove(src)
            return false
        }
        try fileOps.remove(dst)
        return true
    }

    // MARK: - Helpers

    /// Copies a file. The caller made sure that `to` did not exist. If the copy fails, a partial
    /// `to` is removed, unless the failure says that `to` exists (then it is not ours).
    private func copyRemovingPartial(_ from: URL, _ to: URL) throws {
        do {
            try fileOps.copy(from, to)
        } catch {
            if !Self.isFileExists(error), fileOps.exists(to) { try? fileOps.remove(to) }
            throw error
        }
    }

    private static func isFileExists(_ error: Error) -> Bool {
        if (error as? CocoaError)?.code == .fileWriteFileExists { return true }
        let ns = error as NSError
        return ns.domain == NSPOSIXErrorDomain && ns.code == Int(EEXIST)
    }

    private static func pair(_ e: JournalEntry) -> (URL, URL)? {
        guard let s = e.source, let d = e.destination else { return nil }
        return (URL(filePath: s, directoryHint: .notDirectory), URL(filePath: d, directoryHint: .notDirectory))
    }

    /// The path of `url` relative to `folder`, in Unicode NFC form (the form of a `MediaID`).
    private static func relativePath(of url: URL, in folder: URL) -> String {
        let base = folder.path(percentEncoded: false)
        let full = url.path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        let relative = full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
        return relative.precomposedStringWithCanonicalMapping
    }

    private static func entry(_ op: JournalOp, _ src: URL, _ dst: URL) -> JournalEntry {
        JournalEntry(op: op, source: src.path, destination: dst.path, time: .now)
    }

    /// The time stamp of archived journal names, for example `20261023-142501`.
    static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}
