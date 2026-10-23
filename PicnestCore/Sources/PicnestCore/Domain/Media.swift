import Foundation

public enum MediaKind: String, Codable, Sendable, Hashable { case image, video }

/// The relative path from the source folder, in Unicode NFC form.
public typealias MediaID = String

public struct MediaFile: Identifiable, Codable, Sendable, Hashable {
    public var id: MediaID
    public var relativePath: String
    public var kind: MediaKind
    public var size: Int64
    public var modified: Date

    public init(id: MediaID, relativePath: String, kind: MediaKind, size: Int64, modified: Date) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modified = modified
    }
}

public enum DateSource: String, Codable, Sendable, Hashable { case exif, fileNameTimestamp, modificationTime }

public struct PhotoDate: Codable, Sendable, Hashable {
    public var date: Date
    public var source: DateSource

    public init(date: Date, source: DateSource) {
        self.date = date
        self.source = source
    }
}

/// Why the scan skipped a file or folder. `symlink`: a symbolic link to a file or a folder.
public enum SkipReason: String, Codable, Sendable, Hashable {
    case webFile, archive, hidden, filesFolder, outputFolder, unsupported, unreadable, symlink
}

public struct ScanResult: Codable, Sendable, Hashable {
    public var media: [MediaFile]
    public var dates: [MediaID: PhotoDate]
    public var skipped: [SkipReason: Int]

    public init(media: [MediaFile], dates: [MediaID: PhotoDate], skipped: [SkipReason: Int]) {
        self.media = media
        self.dates = dates
        self.skipped = skipped
    }
}
