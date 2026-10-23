import Foundation

/// Collects progress reports from a `@Sendable` callback.
final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(done: Int, total: Int)] = []
    func add(_ done: Int, _ total: Int) { lock.withLock { items.append((done, total)) } }
    var last: (done: Int, total: Int)? { lock.withLock { items.last } }
}
