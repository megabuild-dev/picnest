import Foundation

/// Texts with a count. The catalog holds the one/other forms of each text, so no caller picks a form with `if count == 1`.
/// The `locale` formats the number (for example `2,401`). Callers pass their injected locale.
enum CountText {
    static func photos(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) photos", locale: locale)
    }

    static func folders(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) folders", locale: locale)
    }

    static func files(_ n: Int, locale: Locale = .current) -> String {
        String(localized: "\(n) files", locale: locale)
    }
}
