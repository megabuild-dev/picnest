import Foundation
import Testing
@testable import PicnestCore

@Suite struct LayoutEngineTests {
    private let tol = 1e-3

    /// A4 landscape, margin 36, spacing 24, 3 × 2. Captions are off, so there is no footer.
    private func doc(photos: Int = 6, captions: Bool = false, fileNames: Bool = false) -> LayoutDocument {
        var d = LayoutDocument.new(photos: (0..<photos).map { "p\($0)" }, title: "T")
        d.showsCaptions = captions
        d.showsFileNames = fileNames
        return d
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < tol }

    @Test func a4LandscapeThreeByTwoCellSize() {
        let cells = LayoutEngine.pages(for: doc())[0].cells
        #expect(cells.count == 6)
        for c in cells {
            #expect(near(c.frame.width, 240.6299))
            #expect(near(c.frame.height, 249.6378))
        }
    }

    @Test func a4LandscapeCellOrigins() {
        let cells = LayoutEngine.pages(for: doc())[0].cells
        #expect(near(cells[0].frame.x, 36) && near(cells[0].frame.y, 36))
        #expect(near(cells[4].frame.x, 300.6299) && near(cells[4].frame.y, 309.6378))
        #expect(near(cells[5].frame.maxX, 805.8898) && near(cells[5].frame.maxY, 559.2756))
    }

    @Test func gapsEqualTheSpacing() {
        let c = LayoutEngine.pages(for: doc())[0].cells
        #expect(near(c[1].frame.x - c[0].frame.maxX, 24))
        #expect(near(c[2].frame.x - c[1].frame.maxX, 24))
        #expect(near(c[3].frame.y - c[0].frame.maxY, 24))
    }

    @Test func footerTakesItsBandAndOneGap() {
        let p = LayoutEngine.pages(for: doc(captions: true))[0]
        #expect(near(p.cells[0].frame.height, 217.6378))
        let f = try! #require(p.footer)
        #expect(near(f.y, 519.2756) && near(f.height, 40) && near(f.width, 769.8898))
        #expect(LayoutEngine.pages(for: doc())[0].footer == nil)
    }

    @Test func fileNameBandShrinksTheImageArea() {
        let c = LayoutEngine.pages(for: doc(fileNames: true))[0].cells[0]
        #expect(near(c.imageArea.height, c.frame.height - 14))
        let cap = try! #require(c.caption)
        #expect(near(cap.height, 14) && near(cap.maxY, c.frame.maxY))
        #expect(LayoutEngine.pages(for: doc())[0].cells[0].caption == nil)
    }

    @Test func sevenPhotosOnThreeByTwoMakeTwoPages() {
        let pages = LayoutEngine.pages(for: doc(photos: 7))
        #expect(pages.count == 2)
        #expect(pages[1].cells.count == 6)
        #expect(pages[1].cells.filter { $0.mediaID != nil }.count == 1)
        #expect(pages[1].cells[0].mediaID == "p6")
        #expect(pages[1].cells.filter { $0.mediaID == nil }.count == 5)
    }

    @Test func noPhotosMakeOneEmptyPage() {
        let pages = LayoutEngine.pages(for: doc(photos: 0))
        #expect(pages.count == 1)
        #expect(pages[0].cells.allSatisfy { $0.mediaID == nil })
    }

    @Test func fitLandscapePhotoInACell() {
        let cell = LayoutEngine.pages(for: doc())[0].cells[0]
        let r = LayoutEngine.imageRect(source: PixelSize(width: 4000, height: 3000), in: cell.imageArea, fit: .fit)
        #expect(near(r.width, 240.6299) && near(r.height, 180.4724))
        #expect(near(r.x, 36) && near(r.y, 36 + 34.5827))
    }

    @Test func fillCoversTheArea() {
        let a = LayoutEngine.pages(for: doc())[0].cells[0].imageArea
        let r = LayoutEngine.imageRect(source: PixelSize(width: 4000, height: 3000), in: a, fit: .fill)
        #expect(r.x <= a.x + tol && r.y <= a.y + tol && r.maxX >= a.maxX - tol && r.maxY >= a.maxY - tol)
        #expect(near(r.width / r.height, 4.0 / 3.0))
        #expect(near(r.x + r.width / 2, a.x + a.width / 2))
    }

    @Test func a4LandscapePixelsAt300And150() {
        let s = PaperSize.a4.pageSize(.landscape)
        #expect(LayoutEngine.pixelSize(of: s, dpi: 300) == PixelSize(width: 3508, height: 2480))
        #expect(LayoutEngine.pixelSize(of: s, dpi: 150) == PixelSize(width: 1754, height: 1240))
    }

    @Test func letterLandscapeAt300() {
        let s = PaperSize.letter.pageSize(.landscape)
        #expect(LayoutEngine.pixelSize(of: s, dpi: 300) == PixelSize(width: 3300, height: 2550))
    }

    @Test func neededPixelsIsCappedBySource() {
        let area = LayoutRect(x: 0, y: 0, width: 3508 * 72 / 300, height: 3000)
        #expect(LayoutEngine.neededPixels(for: area, source: PixelSize(width: 640, height: 480), fit: .fit, dpi: 300) == 640)
    }

    @Test func neededPixelsForAFitCell() {
        let cell = LayoutEngine.pages(for: doc())[0].cells[0]
        #expect(LayoutEngine.neededPixels(for: cell.imageArea, source: PixelSize(width: 4000, height: 3000), fit: .fit, dpi: 300) == 1003)
    }

    @Test func hugeSpacingNeverGivesANegativeSize() {
        var d = doc(photos: 20, captions: true, fileNames: true)
        d.paper = .a5
        d.margin = 72
        d.spacing = 72
        d.grid = GridPreset(columns: 5, rows: 4)
        for page in LayoutEngine.pages(for: d) {
            #expect(page.footer.map { $0.width >= 0 && $0.height >= 0 } ?? true)
            for c in page.cells {
                #expect(c.frame.width >= 1 && c.frame.height >= 1)
                #expect(c.imageArea.width >= 0 && c.imageArea.height >= 0)
            }
        }
    }
}
