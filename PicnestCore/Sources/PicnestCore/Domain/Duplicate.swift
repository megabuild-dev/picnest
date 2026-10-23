import Foundation

/// 2 or more photos that are exact copies or look almost the same (spec 3.6, 4.9).
public struct DuplicateGroup: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case exact, similar }

    public var kind: Kind
    /// The photos of the group, best photo first (spec 4.9).
    public var ids: [MediaID]
    /// The photos that clean-up does not move to the Trash. A group always has at least 1.
    public var keepIDs: Set<MediaID>

    public init(kind: Kind, ids: [MediaID], keepIDs: Set<MediaID>) {
        self.kind = kind
        self.ids = ids
        self.keepIDs = keepIDs
    }

    /// The key of the group: its sorted media IDs (spec 14). **Not Duplicates** stores it, so a rescan
    /// that changes the group shows it again.
    public var id: String { Self.key(for: ids) }

    /// The key of a group with these photos, in any order.
    public static func key(for ids: [MediaID]) -> String {
        ids.sorted().joined(separator: "\n")
    }
}

/// The width and height of an image in pixels.
public struct PixelSize: Sendable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
