import Foundation

/// How a search text matches a name: case and diacritic insensitive, as in the Review search.
enum SearchText {
    /// The folded search text, or nil when it is empty or blank.
    static func needle(_ text: String) -> String? {
        let needle = fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return needle.isEmpty ? nil : needle
    }

    /// Lowercase, no diacritics. `đ` has no decomposition, so it folds to `d` by hand.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// True if `name` contains `needle` (a result of `needle(_:)`).
    static func matches(_ name: String, needle: String) -> Bool { fold(name).contains(needle) }
}
