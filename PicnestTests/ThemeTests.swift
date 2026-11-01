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
}
