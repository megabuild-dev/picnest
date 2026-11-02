import Foundation

public typealias CollectionID = UUID

/// A named group of photos that the user made. Named `PhotoCollection` because `Collection` is a Swift protocol.
public struct PhotoCollection: Codable, Sendable, Hashable, Identifiable {
    public var id: CollectionID
    public var name: String
    /// The photos in the collection, in the order the user added them.
    public var memberIDs: [MediaID]
    public var order: Int

    public init(id: CollectionID = UUID(), name: String, memberIDs: [MediaID] = [], order: Int) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.order = order
    }
}

/// Why a collection name is not valid.
public enum CollectionNameIssue: Sendable, Hashable { case empty, duplicate }
