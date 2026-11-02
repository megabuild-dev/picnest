import Foundation

/// The rule that turns many small changes into 1 undo step, shared by the photo editor and the layout editor.
/// The owner shows each value in its history, then calls `change(_:)` with the field that changed.
/// The step ends when a mouse drag ends (`endDrag`), when another field changes, or when `delay` passes with
/// no new change (a key or VoiceOver change has no end event).
@MainActor
final class PendingCommit<Field: Equatable> {
    /// How long a change with no end event waits for the next one.
    var delay: Duration = .milliseconds(600)
    private(set) var field: Field?
    private var isDragging = false
    private let commit: @MainActor () -> Void
    nonisolated(unsafe) private var idle: Task<Void, Never>?

    /// `commit` makes the shown value 1 undo step, and clears any other state of the owner that belongs to it.
    init(commit: @escaping @MainActor () -> Void) { self.commit = commit }

    deinit { idle?.cancel() }

    /// `field` changed. The step of another pending field ends first.
    func change(_ field: Field) {
        if let current = self.field, current != field { commit() }
        self.field = field
        idle?.cancel()
        guard !isDragging else { return }
        let delay = delay
        idle = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// The start of a drag with the mouse: no idle end until `endDrag`.
    func beginDrag() {
        isDragging = true
        idle?.cancel()
    }

    func endDrag() {
        isDragging = false
        finish()
    }

    /// Ends the pending step now.
    func finish() {
        drop()
        commit()
    }

    /// Forgets the pending field with no commit, before undo, redo, or reset. The history drops or keeps the value.
    func drop() {
        idle?.cancel()
        idle = nil
        field = nil
    }
}

/// A chain of preview renders. A new `start` cancels the last render and waits for it, so at most 1 render
/// runs at a time, and a cancelled one skips its work.
@MainActor
final class PreviewChain {
    nonisolated(unsafe) private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    func start(_ work: @escaping @MainActor () async -> Void) {
        let previous = task
        previous?.cancel()
        task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        }
    }

    func cancel() { task?.cancel() }
}
