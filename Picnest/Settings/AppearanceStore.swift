import AppKit
import Observation

/// The appearance choice in Settings (spec 4.1). `system` follows macOS.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// The AppKit appearance to force, or nil to follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Saves the appearance mode in `UserDefaults` (key `appearance`) and applies it to the app.
@MainActor
@Observable
final class AppearanceStore {
    nonisolated static let defaultsKey = "appearance"

    @ObservationIgnored private let defaults: UserDefaults

    /// The chosen mode. Setting it saves it and applies it to the app.
    var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.defaultsKey)
            applyCurrent()
        }
    }

    /// An unknown or missing saved value gives `.system`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.defaultsKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    /// Applies the saved mode to the app. Does nothing when there is no `NSApp` (some test hosts).
    func applyCurrent() {
        NSApp?.appearance = mode.nsAppearance
    }
}
