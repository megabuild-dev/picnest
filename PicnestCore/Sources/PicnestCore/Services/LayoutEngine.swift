import Foundation

public enum ImageFit: Sendable { case fit, fill }

/// One slot of a page. `index` is the position in `LayoutDocument.photoIDs`, also for an empty slot.
/// `imageArea` is `frame` less the caption band. `mediaID` is nil for an empty cell.
public struct LayoutCell: Sendable, Hashable {
    public var frame: LayoutRect
    public var imageArea: LayoutRect
    public var caption: LayoutRect?
    public var mediaID: MediaID?
    public var index: Int
    public var fit: ImageFit

    public init(frame: LayoutRect, imageArea: LayoutRect, caption: LayoutRect?, mediaID: MediaID?, index: Int, fit: ImageFit) {
        self.frame = frame
        self.imageArea = imageArea
        self.caption = caption
        self.mediaID = mediaID
        self.index = index
        self.fit = fit
    }
}

public struct LayoutPage: Sendable, Hashable {
    public var size: PageSize
    public var cells: [LayoutCell]
    public var footer: LayoutRect?

    public init(size: PageSize, cells: [LayoutCell], footer: LayoutRect?) {
        self.size = size
        self.cells = cells
        self.footer = footer
    }
}

/// Pure page geometry in points. It holds no drawing code.
public enum LayoutEngine {
    public static let footerHeight: Double = 40
    public static let captionHeight: Double = 14
    private static let minimumCell: Double = 1

    /// A contact sheet has a footer (title and note) when `showsCaptions` is on.
    /// A collage has 1 page. Its cells come from the template, fill their frame, and have no file-name band.
    public static func pages(for d: LayoutDocument) -> [LayoutPage] {
        let size = d.pageSize
        switch d.kind {
        case .collage:
            let frames = frames(for: d, size: size)
            let cells = frames.grid.enumerated().map { i, frame in
                LayoutCell(frame: frame, imageArea: frame, caption: nil,
                           mediaID: i < d.photoIDs.count ? d.photoIDs[i] : nil, index: i, fit: .fill)
            }
            return [LayoutPage(size: size, cells: cells, footer: frames.footer)]
        case .contactSheet:
            let perPage = max(d.grid.perPage, 1)
            let count = max((d.photoIDs.count + perPage - 1) / perPage, 1)
            let frames = frames(for: d, size: size)
            return (0..<count).map { page in
                let cells = frames.grid.enumerated().map { i, frame -> LayoutCell in
                    let index = page * perPage + i
                    let band = d.showsFileNames ? min(captionHeight, frame.height) : 0
                    return LayoutCell(
                        frame: frame,
                        imageArea: LayoutRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height - band),
                        caption: d.showsFileNames
                            ? LayoutRect(x: frame.x, y: frame.maxY - band, width: frame.width, height: band) : nil,
                        mediaID: index < d.photoIDs.count ? d.photoIDs[index] : nil,
                        index: index,
                        fit: .fit)
                }
                return LayoutPage(size: size, cells: cells, footer: frames.footer)
            }
        }
    }

    /// The cell frames and footer of a page. A spacing that leaves a cell under 1 pt becomes 0.
    private static func frames(for d: LayoutDocument, size: PageSize) -> (grid: [LayoutRect], footer: LayoutRect?) {
        func build(_ spacing: Double) -> (grid: [LayoutRect], footer: LayoutRect?) {
            let c = contentRect(page: size, margin: d.margin, footer: d.showsCaptions, spacing: spacing)
            let rects = d.kind == .collage
                ? split(d.template.root, in: c.grid, spacing: spacing)
                : gridCells(in: c.grid, columns: d.grid.columns, rows: d.grid.rows, spacing: spacing)
            return (rects, c.footer)
        }
        let first = build(d.spacing)
        let fits = first.grid.allSatisfy { $0.width >= minimumCell && $0.height >= minimumCell }
        return fits ? first : build(0)
    }

    /// The cells row by row. A negative size becomes 0.
    public static func gridCells(in content: LayoutRect, columns: Int, rows: Int, spacing: Double) -> [LayoutRect] {
        guard columns > 0, rows > 0 else { return [] }
        let w = max((content.width - spacing * Double(columns - 1)) / Double(columns), 0)
        let h = max((content.height - spacing * Double(rows - 1)) / Double(rows), 0)
        return (0..<rows).flatMap { r in
            (0..<columns).map { c in
                LayoutRect(x: content.x + Double(c) * (w + spacing), y: content.y + Double(r) * (h + spacing),
                           width: w, height: h)
            }
        }
    }

    /// The leaf rectangles of `node`, depth first, left to right, top to bottom. A negative size becomes 0.
    public static func split(_ node: SplitNode, in rect: LayoutRect, spacing: Double) -> [LayoutRect] {
        switch node {
        case .cell:
            return [rect]
        case .row(let children):
            guard !children.isEmpty else { return [] }
            let w = max((rect.width - spacing * Double(children.count - 1)) / Double(children.count), 0)
            return children.enumerated().flatMap { i, child in
                split(child, in: LayoutRect(x: rect.x + Double(i) * (w + spacing), y: rect.y, width: w, height: rect.height),
                      spacing: spacing)
            }
        case .column(let children):
            guard !children.isEmpty else { return [] }
            let h = max((rect.height - spacing * Double(children.count - 1)) / Double(children.count), 0)
            return children.enumerated().flatMap { i, child in
                split(child, in: LayoutRect(x: rect.x, y: rect.y + Double(i) * (h + spacing), width: rect.width, height: h),
                      spacing: spacing)
            }
        }
    }

    /// With a footer, the grid ends `spacing` above it.
    public static func contentRect(page: PageSize, margin: Double, footer: Bool, spacing: Double)
        -> (grid: LayoutRect, footer: LayoutRect?) {
        let w = max(page.width - 2 * margin, 0)
        let h = max(page.height - 2 * margin, 0)
        guard footer else { return (LayoutRect(x: margin, y: margin, width: w, height: h), nil) }
        let fh = min(footerHeight, h)
        let gridHeight = max(h - fh - spacing, 0)
        return (LayoutRect(x: margin, y: margin, width: w, height: gridHeight),
                LayoutRect(x: margin, y: margin + h - fh, width: w, height: fh))
    }

    /// Fit centers the photo inside `area`. Fill covers `area` and centers; the renderer clips to `area`.
    public static func imageRect(source: PixelSize, in area: LayoutRect, fit: ImageFit) -> LayoutRect {
        guard source.width > 0, source.height > 0, area.width > 0, area.height > 0 else {
            return LayoutRect(x: area.x, y: area.y, width: 0, height: 0)
        }
        let sx = area.width / Double(source.width)
        let sy = area.height / Double(source.height)
        let scale = fit == .fit ? min(sx, sy) : max(sx, sy)
        let w = Double(source.width) * scale
        let h = Double(source.height) * scale
        return LayoutRect(x: area.x + (area.width - w) / 2, y: area.y + (area.height - h) / 2, width: w, height: h)
    }

    public static func pixelSize(of page: PageSize, dpi: Int) -> PixelSize {
        PixelSize(width: Int((page.width / 72 * Double(dpi)).rounded()),
                  height: Int((page.height / 72 * Double(dpi)).rounded()))
    }

    /// The longest side, in source pixels, that the drawn rect needs at `dpi`. Never above the longest source side.
    public static func neededPixels(for area: LayoutRect, source: PixelSize, fit: ImageFit, dpi: Int) -> Int {
        let drawn = imageRect(source: source, in: area, fit: fit)
        let needed = Int((max(drawn.width, drawn.height) / 72 * Double(dpi) - 1e-9).rounded(.up))
        return min(max(needed, 0), max(source.width, source.height))
    }
}
