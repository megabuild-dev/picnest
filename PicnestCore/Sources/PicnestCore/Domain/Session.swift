import Foundation

public struct Session: Codable, Sendable, Hashable {
    public var sourcePath: String
    /// Kept only so old files decode. The app always uses **All topics** (`ScanService.candidateList`).
    public var candidateList: CandidateList
    public var categories: [Category]
    public var states: [MediaID: PhotoState]
    public var scan: ScanResult
    public var sortedAt: Date?
    /// Photos the user moved to the Trash (spec 7.4). A trashed photo stays in `scan.media`, so a rescan
    /// can see it, but it has no state, is no example, and is in no view, count, or sort.
    public var trashed: [TrashedPhoto]
    /// The keys (`DuplicateGroup.id`) of the duplicate groups the user marked **Not Duplicates** (spec 3.6).
    public var notDuplicateKeys: Set<String>

    public init(
        sourcePath: String, candidateList: CandidateList, categories: [Category], states: [MediaID: PhotoState],
        scan: ScanResult, sortedAt: Date?, trashed: [TrashedPhoto] = [], notDuplicateKeys: Set<String> = []
    ) {
        self.sourcePath = sourcePath
        self.candidateList = candidateList
        self.categories = categories
        self.states = states
        self.scan = scan
        self.sortedAt = sortedAt
        self.trashed = trashed
        self.notDuplicateKeys = notDuplicateKeys
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath, candidateList, categories, states, scan, sortedAt, trashed, notDuplicateKeys
    }

    /// A `session.json` from before Move to Trash has no `trashed` key. It decodes as no trashed photos.
    /// A `session.json` from before the Duplicates view has no `notDuplicateKeys` key. It decodes as none.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        candidateList = try c.decode(CandidateList.self, forKey: .candidateList)
        categories = try c.decode([Category].self, forKey: .categories)
        states = try c.decode([MediaID: PhotoState].self, forKey: .states)
        scan = try c.decode(ScanResult.self, forKey: .scan)
        sortedAt = try c.decodeIfPresent(Date.self, forKey: .sortedAt)
        trashed = try c.decodeIfPresent([TrashedPhoto].self, forKey: .trashed) ?? []
        notDuplicateKeys = try c.decodeIfPresent(Set<String>.self, forKey: .notDuplicateKeys) ?? []
    }

    /// Writes `notDuplicateKeys` sorted, so the same session always gives the same `session.json`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourcePath, forKey: .sourcePath)
        try c.encode(candidateList, forKey: .candidateList)
        try c.encode(categories, forKey: .categories)
        try c.encode(states, forKey: .states)
        try c.encode(scan, forKey: .scan)
        try c.encodeIfPresent(sortedAt, forKey: .sortedAt)
        try c.encode(trashed, forKey: .trashed)
        try c.encode(notDuplicateKeys.sorted(), forKey: .notDuplicateKeys)
    }

    /// The ids of the trashed photos. The 1 place that says if a photo is trashed.
    public var trashedIDs: Set<MediaID> {
        Set(trashed.map(\.mediaID))
    }

    /// The images that are not trashed and not unreadable: the photos that have embeddings and can be
    /// in duplicate groups.
    public var readableImages: [MediaFile] {
        visibleMedia.filter { $0.kind == .image && states[$0.id] != .unreadable }
    }

    /// The images that are not trashed (videos do not count), and how many of them are "Not sure".
    /// The 1 source of these counts for the Suggest sheet and the Sort hint (spec 3.5, 3.7).
    public var notSureImageCounts: (notSure: Int, images: Int) {
        let images = visibleMedia.filter { $0.kind == .image }
        return (images.filter { states[$0.id]?.isNotSure == true }.count, images.count)
    }

    /// The media files that are not trashed. Views, counts, and sorts use this list, not `scan.media`.
    public var visibleMedia: [MediaFile] {
        let trashed = trashedIDs
        return trashed.isEmpty ? scan.media : scan.media.filter { !trashed.contains($0.id) }
    }
}

/// A photo that the user moved to the Trash (spec 7.4, 10.2).
public struct TrashedPhoto: Codable, Sendable, Hashable {
    public var mediaID: MediaID
    /// The path of the file in the Trash, from `trashItem(at:resultingItemURL:)`.
    public var trashPath: String
    public var time: Date

    public init(mediaID: MediaID, trashPath: String, time: Date) {
        self.mediaID = mediaID
        self.trashPath = trashPath
        self.time = time
    }
}

/// A snapshot of the review state for review undo (spec 3.3).
/// `trashedIDs` is not empty for a Move to Trash step: undo puts those photos back, redo trashes them
/// again. The other fields then hold the state before the photos were trashed.
public struct ReviewChange: Sendable, Hashable {
    public var categories: [Category]
    public var states: [MediaID: PhotoState]
    public var trashedIDs: [MediaID]

    public init(categories: [Category], states: [MediaID: PhotoState], trashedIDs: [MediaID] = []) {
        self.categories = categories
        self.states = states
        self.trashedIDs = trashedIDs
    }
}
