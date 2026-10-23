import Foundation
import Testing
@testable import PicnestCore

private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "test-\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

private func makeFolder(_ dir: TempDir, _ name: String) throws -> URL {
    let url = dir.url.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func sixthRememberDropsOldest() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        let urls = try (0..<6).map { try makeFolder(dir, "f\($0)") }
        for u in urls { try repo.remember(u, photoCount: 1, sortedAt: nil) }
        let recent = repo.recent()
        #expect(recent.count == 5)
        try #require(urls.count >= 6)
        #expect(recent.first?.path == urls[5].standardizedFileURL.path)
        #expect(!recent.contains { $0.path == urls[0].standardizedFileURL.path })
    }
}

@Test func rememberSamePathMovesToTopWithoutDuplicate() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        let a = try makeFolder(dir, "a"), b = try makeFolder(dir, "b")
        try repo.remember(a, photoCount: 1, sortedAt: nil)
        try repo.remember(b, photoCount: 2, sortedAt: nil)
        try repo.remember(a, photoCount: 3, sortedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let recent = repo.recent()
        try #require(recent.count == 2)
        #expect(recent[0].path == a.standardizedFileURL.path)
        #expect(recent[0].photoCount == 3)
        #expect(recent[0].sortedAt != nil)
        #expect(recent[1].path == b.standardizedFileURL.path)
    }
}

@Test func recentPersistsAcrossInstances() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        try BookmarkRepository(defaults: defaults).remember(try makeFolder(dir, "a"), photoCount: 4, sortedAt: nil)
        #expect(BookmarkRepository(defaults: defaults).recent().count == 1)
    }
}

@Test func resolveFollowsRename() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        let old = try makeFolder(dir, "old")
        try repo.remember(old, photoCount: 1, sortedAt: nil)
        let renamed = dir.url.appending(path: "renamed", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: old, to: renamed)
        let resolved = try #require(repo.resolve(repo.recent()[0]))
        #expect(resolved.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
    }
}

@Test func resolveReturnsNilWhenFolderDeleted() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        let f = try makeFolder(dir, "gone")
        try repo.remember(f, photoCount: 1, sortedAt: nil)
        try FileManager.default.removeItem(at: f)
        #expect(repo.resolve(repo.recent()[0]) == nil)
    }
}

@Test func recentFolderIDIgnoresSymlinkSlashAndUnicodeForm() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        let nfc = try makeFolder(dir, "caf\u{E9}")
        try repo.remember(nfc, photoCount: 1, sortedAt: nil)
        let id = repo.recent()[0].id
        let alt = nfc.path.hasPrefix("/private/") ? String(nfc.path.dropFirst("/private".count)) : "/private" + nfc.path
        for variant in [dir.url.appending(path: "cafe\u{301}"), URL(filePath: nfc.path + "/"), URL(filePath: alt)] {
            try repo.remember(variant, photoCount: 1, sortedAt: nil)
            #expect(repo.recent().count == 1)
            #expect(repo.recent()[0].id == id)
        }
    }
}

@Test func forgetRemovesOnlyThatEntry() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        let a = try makeFolder(dir, "a"), b = try makeFolder(dir, "b")
        try repo.remember(a, photoCount: 1, sortedAt: nil)
        try repo.remember(b, photoCount: 2, sortedAt: nil)
        try repo.forget(id: a.canonicalKeyPath)
        #expect(repo.recent().map(\.id) == [b.canonicalKeyPath])
        try repo.forget(id: "/no/such/folder")
        #expect(repo.recent().count == 1)
    }
}

@Test func clearRemovesEveryEntry() throws {
    let dir = try TempDir()
    try withDefaults { defaults in
        let repo = BookmarkRepository(defaults: defaults)
        try repo.remember(try makeFolder(dir, "a"), photoCount: 1, sortedAt: nil)
        try repo.remember(try makeFolder(dir, "b"), photoCount: 1, sortedAt: nil)
        try repo.clear()
        #expect(repo.recent().isEmpty)
    }
}
