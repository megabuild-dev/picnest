import CryptoKit
import Foundation

/// Stores one session per source folder as JSON under `root/<sha256 of path>/session.json`.
public struct SessionRepository: Sendable {
    public static let bundleID = "dev.megabuild.picnest"
    private static let fileName = "session.json"

    public let root: URL

    public init(root: URL = SessionRepository.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        URL.applicationSupportDirectory
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "Sessions", directoryHint: .isDirectory)
    }

    /// Session folder for a source. Other repositories store their files here too.
    public func directory(for source: URL) -> URL {
        let path = source.canonicalKeyPath
        let hex = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appending(path: hex, directoryHint: .isDirectory)
    }

    /// Returns nil when no session exists. Throws when the file is unreadable or corrupt.
    public func load(source: URL) throws -> Session? {
        let file = directory(for: source).appending(path: Self.fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Self.decoder.decode(Session.self, from: Data(contentsOf: file))
    }

    public func save(_ s: Session) throws {
        let dir = directory(for: URL(filePath: s.sourcePath))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.encoder.encode(s).write(to: dir.appending(path: Self.fileName), options: .atomic)
    }

    /// Moves the session of `old` to the key of `new` after the user moved or renamed the source folder.
    /// Replaces any session data of `new` (for example a cancelled scan cache). Updates `sourcePath`.
    /// Returns nil, and changes nothing, when `old` has no session.
    public func relink(from old: URL, to new: URL) throws -> Session? {
        guard var session = try load(source: old) else { return nil }
        let from = directory(for: old), to = directory(for: new)
        if from != to {
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.moveItem(at: from, to: to)
        }
        session.sourcePath = new.canonicalKeyPath
        try save(session)
        return session
    }

    /// Removes only the session file of `source`. The embedding cache, `hashes.json`, and journals stay.
    /// Does nothing when no session file exists.
    public func deleteSessionFile(source: URL) throws {
        let file = directory(for: source).appending(path: Self.fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    public func delete(source: URL) throws {
        let dir = directory(for: source)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }

    // Dates use the default strategy (exact Double) so file mtimes round-trip without loss.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .deferredToDate
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }()
}
