import Foundation

/// Holds a blocking call until the test releases it, so a test can act while file work runs.
/// Call `pass()` from the work (off the main actor). It waits only while the gate is held.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private var waiting = 0
    private let semaphore = DispatchSemaphore(value: 0)

    /// The count of calls that wait in `pass()` now.
    var waitingCount: Int { lock.withLock { waiting } }

    /// Makes each next `pass()` wait until `release()`.
    func hold() { lock.withLock { held = true } }

    /// Lets the waiting calls go on, and stops holding the next ones.
    func release() {
        let count = lock.withLock {
            held = false
            defer { waiting = 0 }
            return waiting
        }
        for _ in 0..<count { semaphore.signal() }
    }

    /// Waits while the gate is held.
    func pass() {
        let wait = lock.withLock {
            if held { waiting += 1 }
            return held
        }
        if wait { semaphore.wait() }
    }

    /// Waits (on the calling actor) until a call waits in `pass()`. Fails the test after 2 s.
    func untilWaiting() async throws {
        let end = Date().addingTimeInterval(2)
        while waitingCount == 0 {
            guard Date() < end else { throw Timeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    struct Timeout: Error {}
}
