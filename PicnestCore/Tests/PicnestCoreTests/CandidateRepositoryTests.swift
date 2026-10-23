import Foundation
import Testing
@testable import PicnestCore

@Test func everydayListSize() throws {
    let c = try CandidateRepository().load(.everyday)
    #expect((40...60).contains(c.count))
    #expect(Set(c.map(\.displayName)).count == c.count)
    #expect(c.allSatisfy { !$0.prompts.isEmpty && !$0.emoji.isEmpty })
}

@Test func artListMatchesCLI() throws {
    let c = try CandidateRepository().load(.artStudio)
    #expect(c.first?.prompts == ["a watercolor painting of a city building"])
    #expect(c.count == 40)
}

/// Phase 12: 1 large list, **All topics** (spec 4.3).
@Test func allListLoadsAndHasNoDuplicateNames() throws {
    let c = try CandidateRepository().load(.all)
    #expect(c.count >= 291)
    #expect(Set(c.map { $0.displayName.lowercased() }).count == c.count)
    #expect(c.allSatisfy { !$0.prompts.isEmpty && $0.prompts.count <= 3 && !$0.emoji.isEmpty })
    #expect(c.allSatisfy { $0.displayName.split(separator: " ").count <= 3 })
}

@Test func allListContainsEverydayAndArtNamesOrSynonyms() throws {
    let names = Set(try CandidateRepository().load(.all).map(\.displayName))
    for name in ["Food", "Receipts", "Workshop event", "Artwork seascape", "Selfies", "Screenshots", "Group photos"] {
        #expect(names.contains(name), "missing \(name)")
    }
    // Synonyms are merged into 1 entry.
    for name in ["Selfie", "Food drink", "Screenshot", "Group photo"] {
        #expect(!names.contains(name), "not merged: \(name)")
    }
}

@Test func oldListsStillLoad() throws {
    #expect(try CandidateRepository().load(.everyday).count == 51)
    #expect(try CandidateRepository().load(.artStudio).count == 40)
}

/// Fix round 1: no 2 entries share an emoji, except the picture frame (no other emoji means a framed picture).
@Test func allListEmojisAreUnique() throws {
    let allowedShared: Set<String> = ["🖼️"]
    let emojis = try CandidateRepository().load(.all).map(\.emoji)
    let shared = Set(emojis.filter { e in emojis.filter { $0 == e }.count > 1 })
    #expect(shared.isSubset(of: allowedShared), "shared: \(shared)")
}

/// Fix round 1: merged and shortened entries keep their old names as aliases. Other entries have none.
@Test func allListKeepsOldNamesAsAliases() throws {
    let all = try CandidateRepository().load(.all)
    var aliasOwner: [String: String] = [:]
    for c in all { for a in c.aliases { aliasOwner[a] = c.displayName } }
    #expect(aliasOwner == [
        "Swimming and water play": "Water play", "Mirror and outfit photos": "Outfit photos",
        "Blurry or dark photos": "Blurry photos", "Selfie": "Selfies", "Food drink": "Food",
        "Screenshot": "Screenshots", "Group photo": "Group photos", "Chat screenshot": "Chat screenshots",
        "Text document": "Documents", "Kids craft": "Kids' artwork",
    ])
    let documents = try #require(all.first { $0.displayName == "Documents" })
    #expect(documents.prompts.contains("a document page with a lot of text"))
    #expect(!documents.prompts.contains { $0.contains("certificate") })
    let tet = try #require(all.first { $0.displayName == "Tet and festivals" })
    #expect(!tet.prompts.contains { $0.contains("lantern") })
    #expect(try CandidateRepository().load(.everyday).allSatisfy { $0.aliases.isEmpty })
}

@Test func candidateWithoutAliasesDecodes() throws {
    let json = Data(#"{"displayName":"Food","emoji":"🍜","prompts":["a photo of food"]}"#.utf8)
    let c = try JSONDecoder().decode(Candidate.self, from: json)
    #expect(c.aliases.isEmpty)
    #expect(c.names == ["Food"])
}
