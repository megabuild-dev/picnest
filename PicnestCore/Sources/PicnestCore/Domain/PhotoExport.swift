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
        others = Set(otherPaths.map { Self.path(of: URL(filePath: $0)) })
    }

    /// True if `url` names a protected file, or is a symlink or hard link to one.
    public func contains(_ url: URL) -> Bool {
        if matches(url) { return true }
        // A symlink at the destination: the file it points to counts.
        let resolved = url.resolvingSymlinksInPath()
        if Self.path(of: resolved) != Self.path(of: url), matches(resolved) { return true }
        return linksToSessionPhoto(url)
    }

    private func matches(_ url: URL) -> Bool {
        let full = Self.path(of: url)
        if others.contains(full) { return true }
        guard full.hasPrefix(root + "/") else { return false }
        return ids.contains(String(full.dropFirst(root.count + 1)))
    }

    /// Only for an existing file that has more than 1 name: it compares the file with each photo of the session.
    private func linksToSessionPhoto(_ url: URL) -> Bool {
        guard let mine = Self.identity(url), mine.links > 1 else { return false }
        let base = URL(filePath: root)
        return ids.contains { id in
            // `ids` are lowercase. On the default volume the lowercase name opens the same file.
            Self.identity(base.appending(path: id))?.id == mine.id
        }
    }

    private static func identity(_ url: URL) -> (id: [Int], links: Int)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
              let dev = (a[.systemNumber] as? NSNumber)?.intValue,
              let ino = (a[.systemFileNumber] as? NSNumber)?.intValue,
              let links = (a[.referenceCount] as? NSNumber)?.intValue else { return nil }
        return ([dev, ino], links)
    }

    /// Canonical folder + name, NFC, lowercase.
    private static func path(of url: URL) -> String {
        key(url.deletingLastPathComponent().canonicalKeyPath + "/" + url.lastPathComponent)
    }

    /// NFC and lowercase, as the default volume (APFS) compares names.
    private static func key(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }
}
