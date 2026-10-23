import Foundation
import PicnestCore

/// In-memory file operations for Trash tests. Nothing touches the disk or the user's Trash.
/// `trash` throws for names in `failTrash`, as on a volume with no Trash.
final class FakeTrashOps: FileOps, @unchecked Sendable {
    struct NoTrash: Error, LocalizedError {
        var errorDescription: String? { "The volume has no Trash." }
    }
    struct Unsupported: Error {}

    private let lock = NSLock()
    private var files: Set<String>
    private var trashCalls = 0
    let failTrash: Set<String>
    /// Hold it to make `trash` wait (a slow Trash move).
    let trashGate = Gate()
    /// Names whose `trash` moves the file but returns no Trash URL.
    let noTrashURL: Set<String>

    init(files: [URL] = [], failTrash: Set<String> = [], noTrashURL: Set<String> = []) {
        self.files = Set(files.map(\.path))
        self.failTrash = failTrash
        self.noTrashURL = noTrashURL
    }

    var trashCount: Int { lock.withLock { trashCalls } }

    func add(_ u: URL) { _ = lock.withLock { files.insert(u.path) } }
    func delete(_ u: URL) { _ = lock.withLock { files.remove(u.path) } }

    func exists(_ u: URL) -> Bool { lock.withLock { files.contains(u.path) } }

    func trash(_ u: URL) throws -> URL? {
        trashGate.pass()
        return try lock.withLock {
            trashCalls += 1
            if failTrash.contains(u.lastPathComponent) { throw NoTrash() }
            guard files.remove(u.path) != nil else { throw CocoaError(.fileNoSuchFile) }
            let t = URL(filePath: "/FakeTrash/\(UUID().uuidString)/\(u.lastPathComponent)")
            if noTrashURL.contains(u.lastPathComponent) { return nil }
            files.insert(t.path)
            return t
        }
    }

    func move(_ from: URL, _ to: URL) throws {
        try lock.withLock {
            guard files.contains(from.path) else { throw CocoaError(.fileNoSuchFile) }
            guard !files.contains(to.path) else { throw CocoaError(.fileWriteFileExists) }
            files.remove(from.path)
            files.insert(to.path)
        }
    }

    func makeFolder(_ u: URL) throws { throw Unsupported() }
    func copy(_ from: URL, _ to: URL) throws { throw Unsupported() }
    func size(_ u: URL) throws -> Int64 { throw Unsupported() }
    func modified(_ u: URL) throws -> Date { throw Unsupported() }
    func remove(_ u: URL) throws { throw Unsupported() }
    func removeEmptyFolder(_ u: URL) throws { throw Unsupported() }
    func isEmptyFolder(_ u: URL) -> Bool { false }
    func names(in folder: URL) -> Set<String> { [] }
}
