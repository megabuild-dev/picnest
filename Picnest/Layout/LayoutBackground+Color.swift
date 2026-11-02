import PicnestCore
import SwiftUI

extension LayoutBackground {
    /// The page color for a swatch. A fixed sRGB value: it does not follow Light or Dark.
    var color: Color { Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1) }
}
