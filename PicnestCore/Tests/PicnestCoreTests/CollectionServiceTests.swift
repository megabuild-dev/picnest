import Foundation
import Testing
@testable import PicnestCore

private func session(_ ids: [MediaID] = ["a.jpg", "b.jpg", "c.jpg"], trashed: [MediaID] = []) -> Session {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let media = ids.map { MediaFile(id: $0, relativePath: $0, kind: .image, size: 10, modified: date) }
    return Session(
        sourcePath: "/x", candidateList: .everyday, categories: [], states: [:],
        scan: ScanResult(media: media, dates: [:], skipped: [:]), sortedAt: nil,
        trashed: trashed.map { TrashedPhoto(mediaID: $0, trashPath: "/t/\($0)", time: date) })
}

@Test func nameIsTrimmedAndEmptyIsInvalid() {
    #expect(CollectionService.validateName("  ", excluding: nil, among: []) == .empty)
    var s = session()
    let id = CollectionService.create(name: "  Trip  ", adding: [], in: &s)
    #expect(s.collections.first { $0.id == id }?.name == "Trip")
    #expect(CollectionService.validateName(" Trip", excluding: nil, among: s.collections) == .duplicate)
}

@Test func nameInNFDIsDuplicateOfNFC() {
    let nfc = "Ẩm thực".precomposedStringWithCanonicalMapping
    let nfd = "Ẩm thực".decomposedStringWithCanonicalMapping
    #expect(Array(nfc.unicodeScalars) != Array(nfd.unicodeScalars))
    let existing = [PhotoCollection(name: nfc, order: 0)]
    #expect(CollectionService.validateName(nfd, excluding: nil, among: existing) == .duplicate)
}

@Test func nameDifferingOnlyInCaseIsDuplicate() {
    let existing = [PhotoCollection(name: "Trip", order: 0)]
    #expect(CollectionService.validateName("tRIP", excluding: nil, among: existing) == .duplicate)
}

@Test func renameToOwnNameIsValid() {
    let c = PhotoCollection(name: "Trip", order: 0)
    #expect(CollectionService.validateName("trip", excluding: c.id, among: [c]) == nil)
}

@Test func toggleFavoriteOnMixedSelectionAddsAll() {
    var s = session()
    s.favoriteIDs = ["a.jpg"]
    #expect(CollectionService.toggleFavorite(["a.jpg", "b.jpg"], in: &s))
    #expect(s.favoriteIDs == ["a.jpg", "b.jpg"])
}

@Test func toggleFavoriteWhenAllAreFavoritesRemovesAll() {
    var s = session()
    s.favoriteIDs = ["a.jpg", "b.jpg", "c.jpg"]
    #expect(CollectionService.toggleFavorite(["a.jpg", "b.jpg"], in: &s))
    #expect(s.favoriteIDs == ["c.jpg"])
}

/// Review Focus 1: 2 exact copies have the same size but different ids. A favorite is for 1 id only.
@Test func favoriteOfOneExactCopyDoesNotMarkTheOther() {
    var s = session(["a.jpg", "copy/a.jpg"])
    #expect(CollectionService.toggleFavorite(["a.jpg"], in: &s))
    #expect(s.favoriteIDs == ["a.jpg"])
    #expect(!s.favoriteIDs.contains("copy/a.jpg"))
}

@Test func unknownAndTrashedIDsAreIgnored() {
    var s = session(trashed: ["c.jpg"])
    #expect(!CollectionService.toggleFavorite(["zzz.jpg", "c.jpg"], in: &s))
    #expect(s.favoriteIDs.isEmpty)
    let id = CollectionService.create(name: "T", adding: ["zzz.jpg", "c.jpg", "a.jpg"], in: &s)!
    #expect(s.collections[0].memberIDs == ["a.jpg"])
    #expect(!CollectionService.add(["zzz.jpg", "c.jpg"], to: id, in: &s))
}

@Test func addKeepsOrderWithoutRepeats() {
    var s = session()
    let id = CollectionService.create(name: "T", adding: ["b.jpg"], in: &s)!
    #expect(CollectionService.add(["c.jpg", "b.jpg", "a.jpg", "c.jpg"], to: id, in: &s))
    #expect(s.collections[0].memberIDs == ["b.jpg", "c.jpg", "a.jpg"])
    #expect(!CollectionService.add(["a.jpg"], to: id, in: &s))
    #expect(CollectionService.remove(["c.jpg", "zzz"], from: id, in: &s))
    #expect(s.collections[0].memberIDs == ["b.jpg", "a.jpg"])
    #expect(!CollectionService.remove(["c.jpg"], from: id, in: &s))
}

@Test func deleteRenumbersOrder() {
    var s = session()
    let a = CollectionService.create(name: "A", adding: [], in: &s)!
    let b = CollectionService.create(name: "B", adding: [], in: &s)!
    _ = CollectionService.create(name: "C", adding: [], in: &s)
    #expect(s.collections.map(\.order) == [0, 1, 2])
    #expect(CollectionService.delete(a, in: &s))
    #expect(s.collections.map(\.name) == ["B", "C"])
    #expect(s.collections.map(\.order) == [0, 1])
    #expect(!CollectionService.delete(a, in: &s))
    #expect(CollectionService.create(name: "B", adding: [], in: &s) == nil)
    #expect(CollectionService.rename(b, to: "Bee", in: &s))
    #expect(!CollectionService.rename(b, to: "C", in: &s))
}

@Test func rekeyMovesFavoritesAndMembers() {
    var s = session()
    s.favoriteIDs = ["a.jpg", "c.jpg"]
    let id = CollectionService.create(name: "T", adding: ["a.jpg", "b.jpg"], in: &s)!
    CollectionService.rekey(["a.jpg": "new/a.jpg"], in: &s)
    #expect(s.favoriteIDs == ["new/a.jpg", "c.jpg"])
    #expect(s.collections.first { $0.id == id }?.memberIDs == ["new/a.jpg", "b.jpg"])
}

@Test func pruneDropsMissingIDs() {
    var s = session()
    s.favoriteIDs = ["a.jpg", "c.jpg"]
    _ = CollectionService.create(name: "T", adding: ["a.jpg", "b.jpg"], in: &s)
    CollectionService.prune(keeping: ["a.jpg", "b.jpg"], in: &s)
    #expect(s.favoriteIDs == ["a.jpg"])
    #expect(s.collections[0].memberIDs == ["a.jpg", "b.jpg"])
    CollectionService.prune(keeping: [], in: &s)
    #expect(s.favoriteIDs.isEmpty && s.collections[0].memberIDs.isEmpty)
}

@Test func visibleFavoritesLeaveOutTrashed() {
    var s = session(trashed: ["b.jpg"])
    s.favoriteIDs = ["a.jpg", "b.jpg"]
    s.collections = [PhotoCollection(name: "T", memberIDs: ["b.jpg", "a.jpg"], order: 0)]
    #expect(CollectionService.visibleFavorites(in: s) == ["a.jpg"])
    #expect(CollectionService.visibleMembers(of: s.collections[0].id, in: s) == ["a.jpg"])
    #expect(CollectionService.visibleMembers(of: UUID(), in: s).isEmpty)
}
