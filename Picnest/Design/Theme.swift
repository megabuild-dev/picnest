import AppKit
import SwiftUI

/// An sRGB color with components from 0 to 1.
struct RGB: Equatable {
    let r, g, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    /// WCAG 2.x relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG 2.x contrast ratio, from 1 to 21.
    func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// A color with one value for light mode and one for dark mode.
struct ThemeColor {
    let light: RGB
    let dark: RGB

    init(light: UInt32, dark: UInt32) {
        self.light = RGB(hex: light)
        self.dark = RGB(hex: dark)
    }

    /// A dynamic color: it picks `dark` when the appearance is dark aqua.
    var color: Color {
        let light = light, dark = dark
        return Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
    }
}

/// All colors and metrics of the app.
/// Sampled from the mockups in `design/`: the light neutrals (background, sidebar, selection) and the
/// accent hue (mockup pink #E2839C).
/// Chosen by hand, because the mockups have no dark mode and no text samples: all dark values,
/// `textPrimary`, `textSecondary`, `surface`, and the status colors (`confirmed`, `needsReview`,
/// `destructive`). The accent is darker than the mockup pink so white text on it reaches 4.5:1.
/// Status colors reach 4.5:1 as text on every ground. `accent` reaches 3:1 on every ground.
enum Theme {
    static let background = ThemeColor(light: 0xFAF7F4, dark: 0x1F1C1D)
    static let sidebar = ThemeColor(light: 0xF7F2F0, dark: 0x191617)
    static let surface = ThemeColor(light: 0xFFFFFF, dark: 0x2A2627)
    static let textPrimary = ThemeColor(light: 0x2B2528, dark: 0xF4F0F1)
    static let textSecondary = ThemeColor(light: 0x6B6166, dark: 0xB5ACB1)
    static let accent = ThemeColor(light: 0xB83E63, dark: 0xC24A6E)
    static let onAccent = ThemeColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Confirmed or kept: score badges, "Changed by you".
    static let confirmed = ThemeColor(light: 0x2A7048, dark: 0x4FB87C)
    /// Text and glyphs on a filled `confirmed` badge (the Keep badge). 5.98:1 in light, 6.58:1 in dark.
    static let onConfirmed = ThemeColor(light: 0xFFFFFF, dark: 0x10241A)
    /// Needs review: "Needs Review", uncertain scores.
    static let needsReview = ThemeColor(light: 0x855000, dark: 0xE0A030)
    static let destructive = ThemeColor(light: 0xB3261E, dark: 0xFF6B63)
    /// Highlight of a chosen card or list row (mockup #F3E3E4). The sidebar rows use the system selection with `accent`.
    static let selection = ThemeColor(light: 0xF3E3E4, dark: 0x3A2A30)

    /// The ground of an image that has not loaded, a progress track, and a key cap, and the glyph on it.
    /// The glyph reaches 3:1 on the fill, as a non-text mark.
    static let placeholderFill = ThemeColor(light: 0xEBE5E2, dark: 0x353031)
    static let placeholderGlyph = ThemeColor(light: 0x847A7F, dark: 0x9A9196)

    /// Dark pill on a photo (used at alpha 0.8) and its text. Same in light and dark, because the photo decides the ground.
    static let badgeBackground = ThemeColor(light: 0x1A1618, dark: 0x1A1618)
    static let onBadge = ThemeColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Alpha of `badgeBackground`. At least 0.7 keeps the text readable on a white photo.
    static let badgeAlpha = 0.8

    /// Shadows and the dim layer behind a blocking overlay. Used at an alpha of 0.12 to 0.2.
    static let shadow = ThemeColor(light: 0x000000, dark: 0x000000)

    /// The ground behind the photo in the editor.
    static let canvasBackground = ThemeColor(light: 0xEFEAE7, dark: 0x141213)
    /// The crop frame, its grid, and its handles. The shade is the dimmed area outside the crop, used at `cropShadeAlpha`.
    static let cropLine = ThemeColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let cropShade = ThemeColor(light: 0x000000, dark: 0x000000)
    static let cropShadeAlpha = 0.45

    enum Metrics {
        static let editorToolRail: CGFloat = 220
        static let editorPanel: CGFloat = 300
        static let filmstripHeight: CGFloat = 96
        static let tileCorner: CGFloat = 10
        static let gridSpacing: CGFloat = 12
        static let sidebarMin: CGFloat = 220
        static let sidebarMax: CGFloat = 250
    }
}
