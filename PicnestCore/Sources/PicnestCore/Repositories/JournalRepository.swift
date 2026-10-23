import Foundation

/// The journal of the last sort: `directory/journal.jsonl`, 1 JSON entry per line.
/// Each line is flushed to disk when it is written, so after a crash the journal matches the disk.
public struct JournalRepository: Sendable {
    static let fileName = "journal.jsonl"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// True when the journal file exists.
    public var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    var file: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    public func append(_ e: JournalEntry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: file])
            }
        }
        var line = try Self.encoder.encode(e)
        line.append(0x0A)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    /// All entries, oldest first. Empty if no journal exists. A last line cut off by a crash
    /// (no newline at the end) is ignored; any other bad line throws.
    public func read() throws -> [JournalEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        let endsWithNewline = data.last == 0x0A
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var entries: [JournalEntry] = []
        for (i, line) in lines.enumerated() {
            do {
                entries.append(try Self.decoder.decode(JournalEntry.self, from: Data(line)))
            } catch {
                if i == lines.count - 1, !endsWithNewline { break }
                throw error
            }
        }
        return entries
    }

    /// nil if no journal exists. True if the last entry is `done`, or if the journal holds no entries.
    public func lastIsComplete() throws -> Bool? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let last = try read().last else { return true }
        return last.op == .done
    }

    /// Renames the journal to `journal.<suffix>.jsonl` (with a number added if that name is taken).
    /// Does nothing if no journal exists.
    public func archive(suffix: String) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var target = directory.appending(path: "journal.\(suffix).jsonl", directoryHint: .notDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appending(path: "journal.\(suffix)-\(n).jsonl", directoryHint: .notDirectory)
            n += 1
        }
        try FileManager.default.moveItem(at: file, to: target)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
