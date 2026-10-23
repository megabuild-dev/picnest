import SwiftUI

/// Colors of the Review screen, from the approved mockup (`notsure-v3.html`). The accent comes from
/// the `AccentColor` asset.
enum ReviewStyle {
    /// Score badge of a photo that is not uncertain, and the "Changed by you" icon.
    static let green = Color(red: 0x3A / 255, green: 0x9A / 255, blue: 0x62 / 255)
    /// Score badge of an uncertain photo, and the "Not sure" icon.
    static let amber = Color(red: 0xC2 / 255, green: 0x7A / 255, blue: 0x12 / 255)
    static let tileCorner: CGFloat = 10
    static let gridSpacing: CGFloat = 12
}
