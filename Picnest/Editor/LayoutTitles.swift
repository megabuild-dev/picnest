import PicnestCore

/// The names that the layout editor shows for the choices of a layout. They are also the accessibility labels.
extension LayoutKind {
    var title: String {
        switch self {
        case .contactSheet: String(localized: "Contact sheet")
        case .collage: String(localized: "Collage")
        }
    }
}

extension PageOrientation {
    var title: String {
        switch self {
        case .landscape: String(localized: "Landscape")
        case .portrait: String(localized: "Portrait")
        }
    }
}

extension LayoutBackground {
    var title: String {
        switch self {
        case .white: String(localized: "White")
        case .cream: String(localized: "Cream")
        case .gray: String(localized: "Gray")
        case .blush: String(localized: "Blush")
        case .charcoal: String(localized: "Charcoal")
        }
    }
}

extension ExportResolution {
    var title: String {
        switch self {
        case .standard: String(localized: "Standard (150 dpi)")
        case .high: String(localized: "High (300 dpi)")
        }
    }
}
