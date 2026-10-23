import Foundation
import Testing
@testable import PicnestCore

struct MediaRepositoryTests {
    private func touch(_ url: URL, _ data: Data = Data("x".utf8)) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    @Test func skipsWebFilesArchivesHiddenAndFilesFolders() throws {
        let dir = try TempDir()
        try TestImages.writeJPEG(to: dir.url.appending(path: "a.jpg"), color: (1, 2, 3))
        try touch(dir.url.appending(path: "page.html"))
        try touch(dir.url.appending(path: "x.zip"))
        try touch(dir.url.appending(path: ".DS_Store"))
        try TestImages.writeJPEG(to: {
            let d = dir.url.appending(path: "site_files", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d.appending(path: "b.jpg")
        }(), color: (1, 2, 3))
        let result = try MediaRepository().scan(source: dir.url, excluding: [])
        #expect(result.media.map(\.id) == ["a.jpg"])
        #expect(result.skipped == [.webFile: 1, .archive: 1, .hidden: 1, .filesFolder: 1])
        #expect(result.dates["a.jpg"] != nil)
    }

    @Test func classifiesKinds() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "a.HEIC"))
        try touch(dir.url.appending(path: "v.MOV"))
        try touch(dir.url.appending(path: "n.txt"))
        let result = try MediaRepository().scan(source: dir.url, excluding: [])
        let kinds = Dictionary(uniqueKeysWithValues: result.media.map { ($0.id, $0.kind) })
        #expect(kinds == ["a.HEIC": .image, "v.MOV": .video])
        #expect(result.skipped == [.unsupported: 1])
        #expect(result.dates.count == 2)
    }

    /// Final review I5: a link to a photo or a folder is skipped. A sort would copy the link, not the photo.
    @Test func skipsSymbolicLinks() throws {
        let dir = try TempDir()
        let source = dir.url.appending(path: "src", directoryHint: .isDirectory)
        let outside = dir.url.appending(path: "outside", directoryHint: .isDirectory)
        for d in [source, outside] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try TestImages.writeJPEG(to: source.appending(path: "real.jpg"), color: (1, 2, 3))
        try TestImages.writeJPEG(to: outside.appending(path: "o.jpg"), color: (1, 2, 3))
        let fm = FileManager.default
        try fm.createSymbolicLink(at: source.appending(path: "link.jpg"), withDestinationURL: outside.appending(path: "o.jpg"))
        try fm.createSymbolicLink(atPath: source.appending(path: "relative.jpg").path, withDestinationPath: "real.jpg")
        try fm.createSymbolicLink(at: source.appending(path: "linked folder"), withDestinationURL: outside)
        let result = try MediaRepository().scan(source: source, excluding: [])
        #expect(result.media.map(\.id) == ["real.jpg"])
        #expect(result.skipped == [.symlink: 3])
    }

    @Test func skipsOutputFolderInsideSource() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "keep.jpg"))
        try touch(dir.url.appending(path: "Zalo - sorted/old.jpg"))
        let out = dir.url.appending(path: "Zalo - sorted", directoryHint: .isDirectory)
        let result = try MediaRepository().scan(source: dir.url, excluding: [out])
        #expect(result.media.map(\.id) == ["keep.jpg"])
        #expect(result.skipped[.outputFolder] == 1)
    }

    @Test func outputFolderMatchesResolvedPath() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "keep.jpg"))
        try touch(dir.url.appending(path: "out/old.jpg"))
        let resolved = dir.url.appending(path: "out", directoryHint: .isDirectory).resolvingSymlinksInPath()
        // Walk the source through the unresolved path (/var/...), exclude through the resolved one (/private/var/...).
        let r = try MediaRepository().scan(source: dir.url, excluding: [resolved])
        #expect(r.media.map(\.id) == ["keep.jpg"])
        #expect(r.skipped[.outputFolder] == 1)
        // And the reverse: resolved source, unresolved exclusion.
        let r2 = try MediaRepository().scan(
            source: dir.url.resolvingSymlinksInPath(),
            excluding: [dir.url.appending(path: "out", directoryHint: .isDirectory)])
        #expect(r2.media.map(\.id) == ["keep.jpg"])
        #expect(r2.skipped[.outputFolder] == 1)
    }

    @Test func outputFolderWithTrailingSlash() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "keep.jpg"))
        try touch(dir.url.appending(path: "out/old.jpg"))
        let slashed = URL(fileURLWithPath: dir.url.path + "/out/")
        #expect(slashed.absoluteString.hasSuffix("/"))
        let r = try MediaRepository().scan(source: dir.url, excluding: [slashed])
        #expect(r.media.map(\.id) == ["keep.jpg"])
        #expect(r.skipped[.outputFolder] == 1)
    }

    @Test func outputFolderNFDOnDiskNFCExcluded() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "keep.jpg"))
        try touch(dir.url.appending(path: "hi\u{0300}nh - sorted/old.jpg"))  // NFD on disk
        let nfc = dir.url.appending(path: "hình - sorted".precomposedStringWithCanonicalMapping, directoryHint: .isDirectory)
        let r = try MediaRepository().scan(source: dir.url, excluding: [nfc])
        #expect(r.media.map(\.id) == ["keep.jpg"])
        #expect(r.skipped[.outputFolder] == 1)
    }

    @Test func unreadableSubfolderIsSkippedAndCounted() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "a.jpg"))
        let locked = dir.url.appending(path: "locked", directoryHint: .isDirectory)
        try touch(locked.appending(path: "b.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let r = try MediaRepository().scan(source: dir.url, excluding: [])
        #expect(r.media.map(\.id) == ["a.jpg"])
        #expect(r.skipped[.unreadable] == 1)
    }

    @Test func unreadableSourceThrowsNoPermission() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: "a.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.path) }
        do {
            _ = try MediaRepository().scan(source: dir.url, excluding: [])
            Issue.record("scan should throw")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadNoPermission)
        }
    }

    @Test func hiddenFolderIsSkippedOnce() throws {
        let dir = try TempDir()
        try touch(dir.url.appending(path: ".hidden/a.jpg"))
        try touch(dir.url.appending(path: ".hidden/b.jpg"))
        let result = try MediaRepository().scan(source: dir.url, excluding: [])
        #expect(result.media.isEmpty)
        #expect(result.skipped == [.hidden: 1])
    }

    @Test func mediaIDIsNFC() throws {
        let dir = try TempDir()
        let nfd = "hi\u{0300}nh/a\u{0309}nh.jpg"
        try touch(dir.url.appending(path: nfd))
        let result = try MediaRepository().scan(source: dir.url, excluding: [])
        let expected = "hình/ảnh.jpg".precomposedStringWithCanonicalMapping
        try #require(result.media.count == 1)
        #expect(result.media[0].id == expected)
        #expect(result.media[0].relativePath == expected)
        let opened = try Data(contentsOf: dir.url.appending(path: result.media[0].relativePath))
        #expect(opened == Data("x".utf8))
    }
}

struct DateResolverTests {
    @Test func exifDateWins() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "1718202933221_x.jpg")
        let exif = Date(timeIntervalSince1970: 1_500_000_000)
        try TestImages.writeJPEG(to: url, color: (1, 2, 3), exifDate: exif)
        let d = DateResolver().date(for: url, modified: Date(timeIntervalSince1970: 5))
        #expect(d.source == .exif)
        #expect(d.date == exif)
    }

    @Test func fileNameTimestamp() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "1718202933221_x.jpg")
        try TestImages.writeJPEG(to: url, color: (1, 2, 3))
        let d = DateResolver().date(for: url, modified: Date(timeIntervalSince1970: 5))
        #expect(d.source == .fileNameTimestamp)
        #expect(d.date == Date(timeIntervalSince1970: 1_718_202_933.221))
        let c = Calendar(identifier: .gregorian)
        var utc = c; utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.dateComponents([.year, .month, .day], from: d.date) == DateComponents(year: 2024, month: 6, day: 12))
    }

    @Test func nonTimestampNameFallsBack() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "z7913505267117_a.jpg")
        try TestImages.writeJPEG(to: url, color: (1, 2, 3))
        let m = Date(timeIntervalSince1970: 5)
        #expect(DateResolver().date(for: url, modified: m) == PhotoDate(date: m, source: .modificationTime))
    }

    @Test func outOfRangeYearFallsBack() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "7956000000000_a.jpg") // year 2222
        try TestImages.writeJPEG(to: url, color: (1, 2, 3))
        let m = Date(timeIntervalSince1970: 5)
        #expect(DateResolver().date(for: url, modified: m).source == .modificationTime)
    }
}
