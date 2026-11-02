import Foundation
import UniformTypeIdentifiers

/// A file format that an export panel can offer.
public protocol ExportFileFormat: CaseIterable, Hashable, Sendable {
    var utType: UTType { get }
    var fileExtension: String { get }
}

public enum LayoutExportFormat: String, ExportFileFormat {
    case png, pdf

    public var utType: UTType { self == .png ? .png : .pdf }
    public var fileExtension: String { rawValue }
}

/// A rectangle in points. The origin is the top left.
public struct LayoutRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// A page size in points (1 pt = 1/72 inch).
public struct PageSize: Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum PageOrientation: String, CaseIterable, Sendable, Codable {
    case landscape, portrait
}

public enum PaperSize: String, CaseIterable, Sendable, Codable {
    case a4, a3, a5, letter

    /// The portrait size.
    public var millimetres: (width: Double, height: Double) {
        switch self {
        case .a4: return (210, 297)
        case .a3: return (297, 420)
        case .a5: return (148, 210)
        case .letter: return (215.9, 279.4)
        }
    }

    public func pageSize(_ o: PageOrientation) -> PageSize {
        let w = millimetres.width / 25.4 * 72
        let h = millimetres.height / 25.4 * 72
        return o == .portrait ? PageSize(width: w, height: h) : PageSize(width: h, height: w)
    }
}

public enum LayoutKind: String, CaseIterable, Sendable, Codable {
    case contactSheet, collage
}

public struct GridPreset: Sendable, Hashable, Codable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// The first 3 are the grids of mockup 05.
    public static let presets: [GridPreset] = [
        GridPreset(columns: 3, rows: 2), GridPreset(columns: 2, rows: 3), GridPreset(columns: 4, rows: 2),
        GridPreset(columns: 4, rows: 3), GridPreset(columns: 5, rows: 4),
    ]

    public var perPage: Int { columns * rows }
}

/// How a collage divides a rectangle. Children share the space equally, with `spacing` between them.
public indirect enum SplitNode: Sendable, Hashable {
    case cell
    case row([SplitNode])
    case column([SplitNode])
}

/// The collage templates.
public enum CollageTemplate: String, CaseIterable, Sendable, Codable {
    case twoByTwo, heroLeft, heroTop, twoOverThree

    public var root: SplitNode {
        switch self {
        case .twoByTwo: return .column([.row([.cell, .cell]), .row([.cell, .cell])])
        case .heroLeft: return .row([.cell, .column([.cell, .cell])])
        case .heroTop: return .column([.cell, .row([.cell, .cell, .cell])])
        case .twoOverThree: return .column([.row([.cell, .cell]), .row([.cell, .cell, .cell])])
        }
    }

    /// How many photos the template shows.
    public var cellCount: Int { root.cellCount }
}

extension SplitNode {
    var cellCount: Int {
        switch self {
        case .cell: return 1
        case .row(let c), .column(let c): return c.reduce(0) { $0 + $1.cellCount }
        }
    }
}

/// The page colors. They are fixed sRGB values and never follow Light or Dark. Sampled from mockup 05.
public enum LayoutBackground: String, CaseIterable, Sendable, Codable {
    case white, cream, gray, blush, charcoal

    public var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .white: return (1, 1, 1)
        case .cream: return (250 / 255, 247 / 255, 241 / 255)
        case .gray: return (238 / 255, 238 / 255, 238 / 255)
        case .blush: return (246 / 255, 238 / 255, 239 / 255)
        case .charcoal: return (58 / 255, 58 / 255, 58 / 255)
        }
    }

    /// The color of the title, captions and footer on this background.
    public var textRGB: (r: Double, g: Double, b: Double) {
        self == .charcoal ? (0.94, 0.94, 0.94) : (0.2, 0.2, 0.2)
    }
}

public enum ExportResolution: Int, CaseIterable, Sendable, Codable {
    case standard = 150, high = 300
}

public struct LayoutDocument: Sendable, Hashable, Codable {
    public static let maxInset: Double = 72

    public var kind: LayoutKind
    public var paper: PaperSize
    public var orientation: PageOrientation
    public var grid: GridPreset
    public var template: CollageTemplate
    public var margin: Double { didSet { margin = Self.clamp(margin) } }
    public var spacing: Double { didSet { spacing = Self.clamp(spacing) } }
    public var background: LayoutBackground
    public var showsCaptions: Bool
    public var showsFileNames: Bool
    public var title: String
    public var note: String
    public var photoIDs: [MediaID]
    public var resolution: ExportResolution

    public init(kind: LayoutKind = .contactSheet, paper: PaperSize = .a4, orientation: PageOrientation = .landscape,
                grid: GridPreset = GridPreset(columns: 3, rows: 2), template: CollageTemplate = .twoByTwo,
                margin: Double = 36, spacing: Double = 24, background: LayoutBackground = .white,
                showsCaptions: Bool = true, showsFileNames: Bool = false, title: String = "", note: String = "",
                photoIDs: [MediaID] = [], resolution: ExportResolution = .high) {
        self.kind = kind
        self.paper = paper
        self.orientation = orientation
        self.grid = grid
        self.template = template
        self.margin = Self.clamp(margin)
        self.spacing = Self.clamp(spacing)
        self.background = background
        self.showsCaptions = showsCaptions
        self.showsFileNames = showsFileNames
        self.title = title
        self.note = note
        self.photoIDs = photoIDs
        self.resolution = resolution
    }

    public static func new(photos: [MediaID], title: String) -> LayoutDocument {
        LayoutDocument(title: title, photoIDs: photos)
    }

    public var pageSize: PageSize { paper.pageSize(orientation) }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), maxInset) }

    private enum CodingKeys: String, CodingKey {
        case kind, paper, orientation, grid, template, margin, spacing, background
        case showsCaptions, showsFileNames, title, note, photoIDs, resolution
    }

    /// Every field falls back to its default, so a field added later does not break an old draft.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LayoutDocument()
        self.init(
            kind: try c.decodeIfPresent(LayoutKind.self, forKey: .kind) ?? d.kind,
            paper: try c.decodeIfPresent(PaperSize.self, forKey: .paper) ?? d.paper,
            orientation: try c.decodeIfPresent(PageOrientation.self, forKey: .orientation) ?? d.orientation,
            grid: try c.decodeIfPresent(GridPreset.self, forKey: .grid) ?? d.grid,
            template: try c.decodeIfPresent(CollageTemplate.self, forKey: .template) ?? d.template,
            margin: try c.decodeIfPresent(Double.self, forKey: .margin) ?? d.margin,
            spacing: try c.decodeIfPresent(Double.self, forKey: .spacing) ?? d.spacing,
            background: try c.decodeIfPresent(LayoutBackground.self, forKey: .background) ?? d.background,
            showsCaptions: try c.decodeIfPresent(Bool.self, forKey: .showsCaptions) ?? d.showsCaptions,
            showsFileNames: try c.decodeIfPresent(Bool.self, forKey: .showsFileNames) ?? d.showsFileNames,
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? d.title,
            note: try c.decodeIfPresent(String.self, forKey: .note) ?? d.note,
            photoIDs: try c.decodeIfPresent([MediaID].self, forKey: .photoIDs) ?? d.photoIDs,
            resolution: try c.decodeIfPresent(ExportResolution.self, forKey: .resolution) ?? d.resolution)
    }
}
