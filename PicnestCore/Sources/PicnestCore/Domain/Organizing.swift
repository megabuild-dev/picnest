import Foundation

/// One file that an in-place organize moved: the old relative path (its `MediaID`) and the new one.
public struct OrganizeMove: Sendable, Hashable {
    public let mediaID: MediaID
    /// The new path, relative to the source folder, in Unicode NFC form.
    public let to: String

    public init(mediaID: MediaID, to: String) {
        self.mediaID = mediaID
        self.to = to
    }
}

/// One file that an in-place organize could not move, and why.
public struct OrganizeFailure: Sendable, Hashable {
    public let mediaID: MediaID
    public let message: String

    public init(mediaID: MediaID, message: String) {
        self.mediaID = mediaID
        self.message = message
    }
}

/// The result of an in-place organize: the files that moved and the ones that did not.
public struct OrganizeResult: Sendable {
    public var moves: [OrganizeMove]
    public var failures: [OrganizeFailure]

    public init(moves: [OrganizeMove] = [], failures: [OrganizeFailure] = []) {
        self.moves = moves
        self.failures = failures
    }
}
