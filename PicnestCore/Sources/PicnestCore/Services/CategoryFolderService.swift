import Foundation

/// Makes, renames, and removes the folder of a category in the source folder. Runs file system calls:
/// call it off the main actor.
public final class CategoryFolderService: Sendable {
    private let fileOps: any FileOps

    public init(fileOps: any FileOps = LocalFileOps()) {
        self.fileOps = fileOps
    }

    /// Makes the folder `name` in `source`. Does nothing if it exists: the app then uses that folder.
    public func ensure(_ name: String, in source: URL) throws {
        let folder = source.appending(path: name, directoryHint: .isDirectory)
        guard !fileOps.exists(folder) else { return }
        try fileOps.makeFolder(folder)
    }

    public func exists(_ name: String, in source: URL) -> Bool {
        fileOps.exists(source.appending(path: name, directoryHint: .isDirectory))
    }

    /// Renames the folder `from` to `to` in `source`. Returns false, and does nothing, if `from` is not
    /// on disk. Never replaces a folder: it throws if `to` exists. A change of letter case only (`Food`
    /// to `food`) goes through a temporary name, because on a case-insensitive volume `to` is `from`.
    @discardableResult
    public func rename(_ from: String, to: String, in source: URL) throws -> Bool {
        let old = source.appending(path: from, directoryHint: .isDirectory)
        let new = source.appending(path: to, directoryHint: .isDirectory)
        guard fileOps.exists(old) else { return false }
        guard from.lowercased() == to.lowercased() else {
            try fileOps.move(old, new)
            return true
        }
        let temporary = source.appending(path: ".picnest-rename-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileOps.move(old, temporary)
        do {
            try fileOps.move(temporary, new)
        } catch {
            try? fileOps.move(temporary, old)
            throw error
        }
        return true
    }
}
