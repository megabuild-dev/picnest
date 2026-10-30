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
}
