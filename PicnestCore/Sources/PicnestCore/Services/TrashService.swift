import Foundation

/// Why a photo could not go to the Trash or come back from it. The `String` is the reason.
public enum TrashError: Error, Equatable, Sendable {
    case cannotTrash(MediaID, String)
    case cannotPutBack(MediaID, String)

    public var mediaID: MediaID {
        switch self {
        case .cannotTrash(let id, _), .cannotPutBack(let id, _): id
        }
    }

    /// The alert text (spec 14 for `cannotTrash`, spec 7.4 for `cannotPutBack`).
    public var message: String {
        switch self {
        case .cannotTrash(_, let reason): "The photo could not be moved to the Trash: \(Self.trimmed(reason))."
        case .cannotPutBack(_, let reason): "The photo could not be put back: \(Self.trimmed(reason))."
        }
    }

    private static func trimmed(_ reason: String) -> String {
        reason.hasSuffix(".") ? String(reason.dropLast()) : reason
    }
}

/// Moves photos to the macOS Trash and puts them back (spec 7.4, 10.1). Never deletes a photo and never
/// overwrites a file. Runs file system calls: call it off the main actor.
public final class TrashService: Sendable {
    static let goneReason = "the file is not in the Trash any more"
    static let takenReason = "a file already exists at its original place"
    static let unknownReason = "its place in the Trash is not known"

    private let fileOps: any FileOps

    public init(fileOps: any FileOps = LocalFileOps()) {
        self.fileOps = fileOps
    }

    /// Moves each file to the Trash. A file that fails stays where it is and is reported in `failed`.
    /// A file that went to the Trash at an unknown place is in `done` with an empty `trashPath`: it is
    /// trashed, but `putBack` cannot find it.
    public func trash(_ items: [(id: MediaID, url: URL)]) -> (done: [TrashedPhoto], failed: [TrashError]) {
        var done: [TrashedPhoto] = []
        var failed: [TrashError] = []
        for item in items {
            do {
                let trashURL = try fileOps.trash(item.url)
                let path = trashURL?.path(percentEncoded: false) ?? ""
                done.append(TrashedPhoto(mediaID: item.id, trashPath: path, time: Date()))
            } catch {
                failed.append(.cannotTrash(item.id, error.localizedDescription))
            }
        }
        return (done, failed)
    }

    /// The ids whose file exists now. Clean-up checks with it that a Keep photo is still on the disk.
    public func existing(_ items: [(id: MediaID, url: URL)]) -> Set<MediaID> {
        Set(items.filter { fileOps.exists($0.url) }.map(\.id))
    }

    /// Moves a trashed file back to `original`. Refuses, and moves nothing, if the Trash file is gone
    /// (the user emptied the Trash) or a file exists at `original`. Returns nil when the file is back.
    public func putBack(_ t: TrashedPhoto, to original: URL) -> TrashError? {
        guard !t.trashPath.isEmpty else { return .cannotPutBack(t.mediaID, Self.unknownReason) }
        let trashURL = URL(filePath: t.trashPath, directoryHint: .notDirectory)
        guard fileOps.exists(trashURL) else { return .cannotPutBack(t.mediaID, Self.goneReason) }
        guard !fileOps.exists(original) else { return .cannotPutBack(t.mediaID, Self.takenReason) }
        do {
            try fileOps.move(trashURL, original)  // Also refuses a file that appeared at `original` just now.
            return nil
        } catch {
            return .cannotPutBack(t.mediaID, error.localizedDescription)
        }
    }
}
