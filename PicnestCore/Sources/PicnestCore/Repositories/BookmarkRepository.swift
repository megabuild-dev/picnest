import Foundation

public struct RecentFolder: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var path: String
    public var bookmark: Data
    public var photoCount: Int
    public var sortedAt: Date?

    public init(id: String, path: String, bookmark: Data, photoCount: Int, sortedAt: Date?) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.photoCount = photoCount
        self.sortedAt = sortedAt
    }
}

/// Remembers the 5 most recent source folders. Uses plain bookmarks (the app has no sandbox).
public struct BookmarkRepository: @unchecked Sendable {
    public static let maxRecent = 5
    private static let key = "recentFolders"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func recent() -> [RecentFolder] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([RecentFolder].self, from: data)) ?? []
    }

    public func remember(_ url: URL, photoCount: Int, sortedAt: Date?) throws {
        let path = url.canonicalKeyPath
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = RecentFolder(id: path, path: path, bookmark: bookmark, photoCount: photoCount, sortedAt: sortedAt)
        var list = recent().filter { $0.id != entry.id }
        list.insert(entry, at: 0)
        defaults.set(try JSONEncoder().encode(Array(list.prefix(Self.maxRecent))), forKey: Self.key)
    }

    /// Removes the entry with `id`, if any.
    public func forget(id: String) throws {
        let list = recent().filter { $0.id != id }
        defaults.set(try JSONEncoder().encode(list), forKey: Self.key)
    }

    /// Removes all entries.
    public func clear() throws {
        defaults.set(try JSONEncoder().encode([RecentFolder]()), forKey: Self.key)
    }

    /// Returns the current URL, even if the folder moved. Nil if it cannot resolve or no longer exists.
    /// Does not change storage. The caller calls `remember` again when the path changed.
    public func resolve(_ f: RecentFolder) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: f.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
