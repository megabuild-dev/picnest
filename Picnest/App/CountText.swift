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

    /// "Page N of M", under the page of the layout editor.
    static func page(_ n: Int, of total: Int, locale: Locale = .current) -> String {
        String(localized: "Page \(n) of \(total)", locale: locale)
    }

    /// "Uses N of M photos", under the photos of a collage.
    static func uses(_ n: Int, of total: Int, locale: Locale = .current) -> String {
        String(localized: "Uses \(n) of \(total) photos", locale: locale)
    }

    /// "Saved N files.", after a layout export.
    static func saved(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "Saved \(n) files.", locale: locale)
    }

    /// "Your last layout has N photos.", in the alert that offers to continue.
    static func lastLayout(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "Your last layout has \(n) photos.", locale: locale)
    }

    /// "N photos in Recently Deleted stay out of the export.", under the page of the layout editor.
    static func leftOut(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) photos in Recently Deleted stay out of the export.", locale: locale)
    }
}
