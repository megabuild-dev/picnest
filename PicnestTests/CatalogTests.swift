import Foundation
import Testing

/// Reads `Picnest/Localizable.xcstrings` as JSON. Every key needs a `translated` value in every language
/// of the catalog, and no key may be stale (spec 4.1, Languages).
struct CatalogTests {
    struct StringUnit: Decodable {
        let state: String?
        let value: String?
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit?
        let variations: Variations?
    }

    struct Variations: Decodable {
        let plural: [String: Localization]?
    }

    struct Entry: Decodable {
        let extractionState: String?
        let shouldTranslate: Bool?
        let localizations: [String: Localization]?
    }

    struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    /// This file is in `PicnestTests/`: 2 steps up from `#filePath` (the file, then `PicnestTests/`) reach the repo root.
    static let catalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()  // PicnestTests/, then the repo root
        .appending(path: "Picnest/Localizable.xcstrings")

    static func load() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
    }

    /// The key with its localizations, for the tests.
    static func catalog() throws -> [String: [String: Localization]] {
        try load().strings.mapValues { $0.localizations ?? [:] }
    }

    /// The units of a localization: the plain unit, or every plural form.
    static func units(of localization: Localization) -> [StringUnit] {
        if let unit = localization.stringUnit { return [unit] }
        return (localization.variations?.plural ?? [:]).values.flatMap(units(of:))
    }

    /// The keys that lack a `translated` value, per language. A language exists when any key has it.
    /// `en` is the source: its values come from the keys, so it is not checked.
    static func missingTranslations(in catalog: Catalog) -> [String: [String]] {
        let languages = Set(catalog.strings.values.flatMap { $0.localizations?.keys ?? [:].keys })
            .subtracting([catalog.sourceLanguage])
        var missing: [String: [String]] = [:]
        for language in languages.sorted() {
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) where entry.shouldTranslate != false {
                let units = entry.localizations?[language].map(units(of:)) ?? []
                let ok = !units.isEmpty && units.allSatisfy { $0.state == "translated" && !($0.value ?? "").isEmpty }
                if !ok { missing[language, default: []].append(key) }
            }
        }
        return missing
    }

    @Test func testEveryKeyHasTranslatedValueInEveryLanguage() throws {
        let catalog = try Self.load()
        #expect(catalog.sourceLanguage == "en")
        let languages = Set(catalog.strings.values.flatMap { $0.localizations?.keys ?? [:].keys })
        #expect(languages.contains("vi"), "The catalog must keep Vietnamese.")
        #expect(Self.missingTranslations(in: catalog).isEmpty,
                "Keys with no translated value, per language: \(Self.missingTranslations(in: catalog))")
    }

    @Test func testMissingTranslationIsFoundInAnyLanguage() {
        let catalog = Catalog(sourceLanguage: "en", strings: [
            "has": Entry(extractionState: nil, shouldTranslate: nil, localizations: [
                "vi": Localization(stringUnit: StringUnit(state: "translated", value: "v"), variations: nil),
                "fr": Localization(stringUnit: StringUnit(state: "translated", value: "f"), variations: nil)]),
            "noFr": Entry(extractionState: nil, shouldTranslate: nil, localizations: [
                "vi": Localization(stringUnit: StringUnit(state: "translated", value: "v"), variations: nil)]),
            "skipped": Entry(extractionState: nil, shouldTranslate: false, localizations: nil),
        ])
        #expect(Self.missingTranslations(in: catalog) == ["fr": ["noFr"]])
    }

    @Test func testNoStaleKeys() throws {
        let stale = try Self.load().strings.filter { $0.value.extractionState == "stale" }.keys.sorted()
        #expect(stale.isEmpty, "Stale keys: \(stale)")
    }
}
