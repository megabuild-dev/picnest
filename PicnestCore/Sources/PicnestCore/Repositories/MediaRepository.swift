import Foundation

/// Scans a source folder for photos and videos and applies the skip rules.
public struct MediaRepository: Sendable {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tiff"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    static let webExtensions: Set<String> = ["html", "htm", "css", "js"]
    static let archiveExtensions: Set<String> = ["zip"]

    private let dates = DateResolver()

    public init() {}

    public func scan(source: URL, excluding: [URL]) throws -> ScanResult {
        let fm = FileManager.default
        let excluded = Set(excluding.map { Self.key($0) })
        var media: [MediaFile] = []
        var skipped: [SkipReason: Int] = [:]

        func walk(_ folder: URL, _ prefix: String) throws {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
            let urls: [URL]
            do {
                urls = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
            } catch {
                if prefix.isEmpty { throw error }  // The source folder itself: report the error.
                skipped[.unreadable, default: 0] += 1
                return
            }
            for url in urls {
                let name = url.lastPathComponent
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                    skipped[.unreadable, default: 0] += 1
                    continue
                }
                let isDir = values.isDirectory ?? false
                if name.hasPrefix(".") { skipped[.hidden, default: 0] += 1; continue }
                // A link is not walked or sorted: a sort would copy the link, not the photo (final review I5).
                if values.isSymbolicLink == true { skipped[.symlink, default: 0] += 1; continue }
                if isDir {
                    if excluded.contains(Self.key(url)) { skipped[.outputFolder, default: 0] += 1; continue }
                    if name.hasSuffix("_files") { skipped[.filesFolder, default: 0] += 1; continue }
                    try walk(url, prefix + name + "/")
                    continue
                }
                let ext = url.pathExtension.lowercased()
                if Self.webExtensions.contains(ext) { skipped[.webFile, default: 0] += 1; continue }
                if Self.archiveExtensions.contains(ext) { skipped[.archive, default: 0] += 1; continue }
                let kind: MediaKind
                if Self.imageExtensions.contains(ext) { kind = .image }
                else if Self.videoExtensions.contains(ext) { kind = .video }
                else { skipped[.unsupported, default: 0] += 1; continue }
                let path = (prefix + name).precomposedStringWithCanonicalMapping
                media.append(MediaFile(
                    id: path, relativePath: path, kind: kind,
                    size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
            }
        }
        try walk(source, "")
        media.sort { $0.id < $1.id }
        var dateMap: [MediaID: PhotoDate] = [:]
        for file in media {
            dateMap[file.id] = dates.date(for: source.appending(path: file.relativePath), modified: file.modified)
        }
        return ScanResult(media: media, dates: dateMap, skipped: skipped)
    }

    private static func key(_ url: URL) -> String {
        url.canonicalKeyPath
    }
}
