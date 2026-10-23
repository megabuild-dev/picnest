import Foundation
import Testing
@testable import PicnestCore

private func makeSession(source: String) -> Session {
    let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
    let cat = UUID()
    let file = MediaFile(id: "a.jpg", relativePath: "a.jpg", kind: .image, size: 10, modified: date)
    return Session(
        sourcePath: source,
        candidateList: .everyday,
        categories: [Category(id: cat, displayName: "Food", emoji: "🍜", prompts: ["a photo of food"], exampleIDs: [], order: 0)],
        states: ["a.jpg": .manual(cat)],
        scan: ScanResult(media: [file], dates: ["a.jpg": PhotoDate(date: date, source: .exif)], skipped: [.hidden: 1]),
        sortedAt: date
    )
}

@Test func sessionSaveThenLoadIsEqual() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    let s = makeSession(source: source.path)
    try repo.save(s)
    #expect(try repo.load(source: source) == s)
}

@Test func sessionLoadReturnsNilWhenMissing() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    #expect(try repo.load(source: URL(filePath: "/x/none")) == nil)
}

@Test func sessionLoadThrowsOnCorruptJSON() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    try FileManager.default.createDirectory(at: repo.directory(for: source), withIntermediateDirectories: true)
    try Data("nope".utf8).write(to: repo.directory(for: source).appending(path: "session.json"))
    #expect(throws: (any Error).self) { try repo.load(source: source) }
}

@Test func sessionDeleteRemovesFolder() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    try repo.save(makeSession(source: source.path))
    #expect(FileManager.default.fileExists(atPath: repo.directory(for: source).path))
    try repo.delete(source: source)
    #expect(!FileManager.default.fileExists(atPath: repo.directory(for: source).path))
}

@Test func sessionFolderNameIsSha256Hex() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let name = repo.directory(for: URL(filePath: "/x/src")).lastPathComponent
    #expect(name.count == 64 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    #expect(name != repo.directory(for: URL(filePath: "/x/other")).lastPathComponent)
    #expect(name == repo.directory(for: URL(filePath: "/x/./src")).lastPathComponent)
}

@Test func sessionPreservesFileModifiedDateExactly() throws {
    let dir = try TempDir()
    let file = dir.url.appending(path: "p.jpg")
    try Data([1]).write(to: file)
    let mtime = try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    var s = makeSession(source: dir.url.path)
    s.scan.media = [MediaFile(id: "p.jpg", relativePath: "p.jpg", kind: .image, size: 1, modified: mtime)]
    let repo = SessionRepository(root: dir.url.appending(path: "sessions"))
    try repo.save(s)
    let loaded = try #require(try repo.load(source: dir.url))
    let fresh = try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    try #require(loaded.scan.media.count >= 1)
    #expect(loaded.scan.media[0].modified == fresh)
}

@Test func sessionDirectoryIgnoresSymlinkSlashAndUnicodeForm() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url.appending(path: "sessions"))
    let nfc = dir.url.appending(path: "caf\u{E9}", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: nfc, withIntermediateDirectories: true)
    let nfd = dir.url.appending(path: "cafe\u{301}", directoryHint: .isDirectory)
    let base = repo.directory(for: nfc)
    #expect(repo.directory(for: nfd) == base)
    #expect(repo.directory(for: URL(filePath: nfc.path + "/")) == base)
    let alt = nfc.path.hasPrefix("/private/") ? String(nfc.path.dropFirst("/private".count)) : "/private" + nfc.path
    #expect(repo.directory(for: URL(filePath: alt)) == base)
}

/// Review Focus 1: a `session.json` from before Move to Trash has no `trashed` key. It must open.
@Test func oldSessionWithoutTrashedDecodes() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    let s = makeSession(source: source.path)
    try repo.save(s)
    let file = repo.directory(for: source).appending(path: "session.json")
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(json["trashed"] != nil)
    json.removeValue(forKey: "trashed")
    try JSONSerialization.data(withJSONObject: json).write(to: file)

    let loaded = try #require(try repo.load(source: source))
    #expect(loaded.trashed == [])
    #expect(loaded == s)
}

@Test func sessionWithTrashedRoundTrips() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    var s = makeSession(source: source.path)
    s.trashed = [TrashedPhoto(mediaID: "a.jpg", trashPath: "/Users/x/.Trash/a.jpg", time: Date(timeIntervalSince1970: 1_700_000_001.5))]
    try repo.save(s)
    #expect(try repo.load(source: source) == s)
    #expect(try repo.load(source: source)?.trashedIDs == ["a.jpg"])
}

/// Review Focus 1: a `session.json` from before the Duplicates view has no `notDuplicateKeys` key.
@Test func oldSessionWithoutNotDuplicateKeysDecodes() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    let s = makeSession(source: source.path)
    try repo.save(s)
    let file = repo.directory(for: source).appending(path: "session.json")
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(json["notDuplicateKeys"] != nil)
    json.removeValue(forKey: "notDuplicateKeys")
    json.removeValue(forKey: "trashed")
    try JSONSerialization.data(withJSONObject: json).write(to: file)

    let loaded = try #require(try repo.load(source: source))
    #expect(loaded.notDuplicateKeys == [])
    #expect(loaded == s)
}

@Test func sessionWithNotDuplicateKeysRoundTrips() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    var s = makeSession(source: source.path)
    s.notDuplicateKeys = [DuplicateGroup.key(for: ["b.jpg", "a.jpg"])]
    try repo.save(s)
    #expect(try repo.load(source: source)?.notDuplicateKeys == s.notDuplicateKeys)
}

@Test func oldSettingsWithoutDuplicateSimilarityDecode() throws {
    let json = Data(#"{"minScore":0.2,"minMargin":0.02,"temperature":0.01,"exampleScale":1,"exampleOffset":0}"#.utf8)
    let settings = try JSONDecoder().decode(ClassifySettings.self, from: json)
    #expect(settings.duplicateSimilarity == 0.95)
    #expect(ClassifySettings.default.duplicateSimilarity == 0.95)
    let again = try JSONDecoder().decode(ClassifySettings.self, from: JSONEncoder().encode(settings))
    #expect(again == settings)
}

@Test func notDuplicateKeysAreSavedSorted() throws {
    var s = makeSession(source: "/x/src")
    s.notDuplicateKeys = ["c", "a", "b", "e", "d"]
    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    #expect(json["notDuplicateKeys"] as? [String] == ["a", "b", "c", "d", "e"])
}

/// Final review M2: a session with every field set saves and loads equal. The custom `encode` must write
/// every field: the test also checks that the JSON has 1 key for each stored property.
@Test func sessionWithEveryFieldRoundTrips() throws {
    let dir = try TempDir()
    let repo = SessionRepository(root: dir.url)
    let source = URL(filePath: "/x/src")
    let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
    let food = UUID(), docs = UUID()
    let names = ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg", "f.mov", "g.jpg"]
    let media = names.map {
        MediaFile(id: $0, relativePath: "sub/\($0)", kind: $0.hasSuffix(".mov") ? .video : .image, size: 10,
                  modified: date)
    }
    let sure = Assignment(categoryID: food, score: 0.31, secondCategoryID: docs, secondScore: 0.2, percent: 91,
                          uncertain: false)
    let unsure = Assignment(categoryID: docs, score: 0.25, secondCategoryID: nil, secondScore: nil, percent: 51,
                            uncertain: true)
    let s = Session(
        sourcePath: source.path, candidateList: .artStudio,
        categories: [
            Category(id: food, displayName: "Food", emoji: "🍜", prompts: ["a photo of food", "a meal"],
                     exampleIDs: ["b.jpg"], order: 0),
            Category(id: docs, displayName: "Docs", emoji: "📄", prompts: ["a photo of a document"],
                     exampleIDs: [], order: 1),
        ],
        states: [
            "a.jpg": .auto(sure), "b.jpg": .manual(food), "c.jpg": .heldNotSure(unsure), "d.jpg": .dontMove,
            "e.jpg": .unreadable,
        ],
        scan: ScanResult(
            media: media,
            dates: ["a.jpg": PhotoDate(date: date, source: .exif), "b.jpg": PhotoDate(date: date, source: .fileNameTimestamp),
                    "c.jpg": PhotoDate(date: date, source: .modificationTime)],
            skipped: [.hidden: 1, .symlink: 2, .webFile: 3]),
        sortedAt: date.addingTimeInterval(60),
        trashed: [TrashedPhoto(mediaID: "g.jpg", trashPath: "/Users/x/.Trash/g.jpg", time: date.addingTimeInterval(5))],
        notDuplicateKeys: [DuplicateGroup.key(for: ["a.jpg", "b.jpg"]), DuplicateGroup.key(for: ["c.jpg", "d.jpg"])])

    try repo.save(s)
    #expect(try repo.load(source: source) == s)

    let file = repo.directory(for: source).appending(path: "session.json")
    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let fields = Set(Mirror(reflecting: s).children.compactMap(\.label))
    #expect(fields.count == 8)
    #expect(Set(json.keys) == fields)

    // A `session.json` from before Move to Trash and the Duplicates view has neither new key.
    var old = json
    old.removeValue(forKey: "trashed")
    old.removeValue(forKey: "notDuplicateKeys")
    try JSONSerialization.data(withJSONObject: old).write(to: file)
    var expected = s
    expected.trashed = []
    expected.notDuplicateKeys = []
    #expect(try repo.load(source: source) == expected)
}
