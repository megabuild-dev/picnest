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

extension GridPreset {
    /// "3 × 2": columns by rows.
    var title: String { "\(columns) × \(rows)" }
}

extension GridPreset {
    /// The grid as a split, for the drawn preview.
    var previewNode: SplitNode {
        .column(Array(repeating: .row(Array(repeating: .cell, count: columns)), count: rows))
    }
}

extension CollageTemplate {
    var title: String {
        switch self {
        case .twoByTwo: String(localized: "Two by two")
        case .heroLeft: String(localized: "Large left")
        case .heroTop: String(localized: "Large top")
        case .twoOverThree: String(localized: "Two over three")
        }
    }
}
