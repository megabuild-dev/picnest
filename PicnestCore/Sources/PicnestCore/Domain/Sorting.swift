import Foundation

public enum SortMode: String, Codable, Sendable, Hashable { case copy, move }

public enum NotSureChoice: String, Codable, Sendable, Hashable {
    case acceptBestGuess, notSureFolder, leaveInSource
}

public struct SortOptions: Codable, Sendable, Hashable {
    public var destination: URL
    public var mode: SortMode
    public var dateFolders: Bool
    public var rename: Bool
    public var notSureChoice: NotSureChoice

    public init(destination: URL, mode: SortMode, dateFolders: Bool, rename: Bool, notSureChoice: NotSureChoice) {
        self.destination = destination
        self.mode = mode
        self.dateFolders = dateFolders
        self.rename = rename
        self.notSureChoice = notSureChoice
    }

    /// Copy, no date folders, no rename, accept best guess. Destination is `<source> - sorted` next to the source.
    public static func defaults(source: URL) -> SortOptions {
        let name = source.lastPathComponent + " - sorted"
        return SortOptions(
            destination: source.deletingLastPathComponent().appending(path: name, directoryHint: .isDirectory),
            mode: .copy, dateFolders: false, rename: false, notSureChoice: .acceptBestGuess)
    }
}

public struct PlanEntry: Codable, Sendable, Hashable {
    public var mediaID: MediaID
    public var source: URL
    public var destination: URL
    public var size: Int64
    public var modified: Date

    public init(mediaID: MediaID, source: URL, destination: URL, size: Int64, modified: Date) {
        self.mediaID = mediaID
        self.source = source
        self.destination = destination
        self.size = size
        self.modified = modified
    }
}

public enum JournalOp: String, Codable, Sendable, Hashable { case mkdir, copy, move, done }

public struct JournalEntry: Codable, Sendable, Hashable {
    public var op: JournalOp
    public var source: String?
    public var destination: String?
    public var time: Date

    public init(op: JournalOp, source: String?, destination: String?, time: Date) {
        self.op = op
        self.source = source
        self.destination = destination
        self.time = time
    }
}
