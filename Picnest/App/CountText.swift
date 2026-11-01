import Foundation

/// Texts with a count. The catalog holds the one/other forms of each text, so no caller picks a form with `if count == 1`.
/// The `locale` formats the number (for example `2,401`). Callers pass their injected locale.
enum CountText {
    static func photos(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) photos", locale: locale)
    }

    /// "N photos need a quick check", the line under the Needs Review title.
    static func needQuickCheck(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) photos need a quick check", locale: locale)
    }

    /// "N photos selected", the title of the inspector with many photos selected.
    static func photosSelected(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) photos selected", locale: locale)
    }

    /// "Add N Photos", the button of the Add Photos sheet.
    static func addPhotos(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "Add \(n) Photos", locale: locale)
    }

    /// "N photos in this set", under the filmstrip of the photo editor.
    static func inSet(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) photos in this set", locale: locale)
    }

    static func folders(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) folders", locale: locale)
    }

    static func files(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) files", locale: locale)
    }
}
