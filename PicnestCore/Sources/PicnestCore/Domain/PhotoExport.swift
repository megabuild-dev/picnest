import Foundation

public enum PhotoExportError: Error, Equatable, Sendable {
    /// The destination is the original or another photo of the session.
    case wouldReplaceOriginal
    case originalMissing
    case cannotRead
    case cannotWrite(String)
}

/// The photos that an export must never replace: the photos of the session and the files in the Trash.
/// The init reads the disk 1 time (the source folder). `contains` reads the disk 1 time, for the folder
/// of the URL.
public struct ProtectedFiles: Sendable {
    private let root: String
    private let ids: Set<String>
    private let others: Set<String>

    /// `mediaIDs` are paths relative to `source`. `otherPaths` are full paths (the `trashPath` values).
    public init(source: URL, mediaIDs: Set<MediaID>, otherPaths: [String]) {
        root = Self.key(source.canonicalKeyPath)
        ids = Set(mediaIDs.map(Self.key))
        others = Set(otherPaths.map { Self.key(URL(filePath: $0).standardizedFileURL.path) })
    }

    public func contains(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().canonicalKeyPath
        let full = Self.key(parent + "/" + url.lastPathComponent)
        if others.contains(full) { return true }
        guard full.hasPrefix(root + "/") else { return false }
        return ids.contains(String(full.dropFirst(root.count + 1)))
    }

    /// NFC and lowercase, as the default volume (APFS) compares names.
    private static func key(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }
}
