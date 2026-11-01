import Foundation
import Observation

/// The language choice in Settings. `system` follows macOS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, vi

    var id: String { rawValue }

    /// The name in the picker. English and Tiếng Việt never change by language.
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .en: "English"
        case .vi: "Tiếng Việt"
        }
    }
}

/// Saves the language in `UserDefaults` under `AppleLanguages`. The change takes effect on the next launch.
@MainActor
@Observable
final class LanguageStore {
    nonisolated static let defaultsKey = "AppleLanguages"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let launchLanguage: AppLanguage

    /// The chosen language. Setting it writes `AppleLanguages`, or removes it for `.system`.
    var language: AppLanguage {
        didSet {
            if language == .system {
                defaults.removeObject(forKey: Self.defaultsKey)
            } else {
                defaults.set([language.rawValue], forKey: Self.defaultsKey)
            }
        }
    }

    /// True when the language differs from the one at launch.
    var needsRestart: Bool { language != launchLanguage }

    /// An unknown or missing saved code gives `.system`. `domain` is the persistent domain of `defaults`.
    /// It reads that domain only, so a launch argument such as `-AppleLanguages (en)` does not hide the saved value.
    init(defaults: UserDefaults, domain: String = Bundle.main.bundleIdentifier ?? "") {
        // A missing bundle id falls back to "", a domain with no saved value, so it reads as System.
        self.defaults = defaults
        let codes = defaults.persistentDomain(forName: domain)?[Self.defaultsKey] as? [String]
        let saved = codes?.first.flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = saved
        launchLanguage = saved
    }
}
