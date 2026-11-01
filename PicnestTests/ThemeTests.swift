import AppKit
import XCTest
@testable import Picnest

final class ThemeTests: XCTestCase {
    func testContrastOfBlackOnWhiteIs21() {
        XCTAssertEqual(RGB(r: 0, g: 0, b: 0).contrast(with: RGB(r: 1, g: 1, b: 1)), 21, accuracy: 0.01)
    }

    func testBodyTextContrastInLightAndDark() {
        let texts: [(String, ThemeColor)] = [("textPrimary", Theme.textPrimary), ("textSecondary", Theme.textSecondary)]
        let grounds: [(String, ThemeColor)] = [("background", Theme.background), ("surface", Theme.surface), ("sidebar", Theme.sidebar)]
        for (textName, text) in texts {
            for (groundName, ground) in grounds {
                XCTAssertGreaterThanOrEqual(text.light.contrast(with: ground.light), 4.5, "\(textName) on \(groundName), light")
                XCTAssertGreaterThanOrEqual(text.dark.contrast(with: ground.dark), 4.5, "\(textName) on \(groundName), dark")
            }
        }
    }

    func testOnAccentContrastOnAccent() {
        XCTAssertGreaterThanOrEqual(Theme.onAccent.light.contrast(with: Theme.accent.light), 4.5)
        XCTAssertGreaterThanOrEqual(Theme.onAccent.dark.contrast(with: Theme.accent.dark), 4.5)
    }

    private var grounds: [(String, ThemeColor)] {
        [("background", Theme.background), ("surface", Theme.surface), ("sidebar", Theme.sidebar), ("selection", Theme.selection)]
    }

    func testStatusColorsAreReadableAsTextOnEveryGround() {
        let statuses: [(String, ThemeColor)] = [("needsReview", Theme.needsReview), ("confirmed", Theme.confirmed), ("destructive", Theme.destructive)]
        for (name, status) in statuses {
            for (groundName, ground) in grounds {
                XCTAssertGreaterThanOrEqual(status.light.contrast(with: ground.light), 4.5, "\(name) on \(groundName), light")
                XCTAssertGreaterThanOrEqual(status.dark.contrast(with: ground.dark), 4.5, "\(name) on \(groundName), dark")
            }
        }
    }

    func testAccentHasNonTextContrastOnGrounds() {
        for (groundName, ground) in grounds.filter({ $0.0 != "selection" }) {
            XCTAssertGreaterThanOrEqual(Theme.accent.light.contrast(with: ground.light), 3.0, "accent on \(groundName), light")
            XCTAssertGreaterThanOrEqual(Theme.accent.dark.contrast(with: ground.dark), 3.0, "accent on \(groundName), dark")
        }
    }

    func testColorResolvesPerAppearance() throws {
        let accent = Theme.accent
        XCTAssertNotEqual(accent.light, accent.dark)
        let resolved: (NSAppearance.Name) throws -> RGB = { name in
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var rgb: RGB?
            appearance.performAsCurrentDrawingAppearance {
                let c = NSColor(accent.color).usingColorSpace(.sRGB)!
                rgb = RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
            }
            return try XCTUnwrap(rgb)
        }
        let light = try resolved(.aqua), dark = try resolved(.darkAqua)
        for (got, want) in [(light, accent.light), (dark, accent.dark)] {
            XCTAssertEqual(got.r, want.r, accuracy: 0.003)
            XCTAssertEqual(got.g, want.g, accuracy: 0.003)
            XCTAssertEqual(got.b, want.b, accuracy: 0.003)
        }
    }
}
