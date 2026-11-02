import Foundation
import Testing
@testable import PicnestCore

@Suite struct LayoutTypesTests {
    @Test func a4LandscapeIsExactInPoints() {
        let s = PaperSize.a4.pageSize(.landscape)
        #expect(abs(s.width - 841.8898) < 1e-4)
        #expect(abs(s.height - 595.2756) < 1e-4)
    }

    @Test func a4PortraitSwapsTheSides() {
        let s = PaperSize.a4.pageSize(.portrait)
        #expect(abs(s.width - 595.2756) < 1e-4)
        #expect(abs(s.height - 841.8898) < 1e-4)
    }

    @Test func letterIsSixHundredTwelveBySevenNinetyTwo() {
        let s = PaperSize.letter.pageSize(.portrait)
        #expect(abs(s.width - 612) < 0.01)
        #expect(abs(s.height - 792) < 0.01)
    }

    @Test func marginAndSpacingAreClamped() {
        var d = LayoutDocument.new(photos: [], title: "T")
        d.margin = -5
        d.spacing = 100
        #expect(d.margin == 0)
        #expect(d.spacing == 72)
    }

    @Test func newDocumentIsAContactSheetOnA4Landscape() {
        let d = LayoutDocument.new(photos: ["a", "b"], title: "Trip")
        #expect(d.kind == .contactSheet)
        #expect(d.paper == .a4)
        #expect(d.orientation == .landscape)
        #expect(d.grid == GridPreset(columns: 3, rows: 2))
        #expect(d.photoIDs == ["a", "b"])
        #expect(d.margin == 36 && d.spacing == 24)
        #expect(d.showsCaptions && !d.showsFileNames)
        #expect(d.resolution == .high)
    }

    @Test func documentRoundTripsThroughJSON() throws {
        var d = LayoutDocument.new(photos: ["a"], title: "Trip")
        d.background = .blush
        d.resolution = .standard
        let back = try JSONDecoder().decode(LayoutDocument.self, from: JSONEncoder().encode(d))
        #expect(back == d)
    }

    @Test func oldDraftWithoutResolutionDecodes() throws {
        var d = LayoutDocument.new(photos: ["a"], title: "Trip")
        d.background = .cream
        let data = try JSONEncoder().encode(d)
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "resolution")
        let old = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(LayoutDocument.self, from: old)
        #expect(back.resolution == .high)
        #expect(back.background == .cream)
    }

    @Test func presetsStartWithTheMockupGrids() {
        let p = GridPreset.presets
        #expect(Array(p.prefix(3)) == [GridPreset(columns: 3, rows: 2), GridPreset(columns: 2, rows: 3), GridPreset(columns: 4, rows: 2)])
        #expect(p.count == 5)
        #expect(p[0].perPage == 6)
    }

    @Test func genericHistoryUndoesAnyValue() {
        var h = History<Int>(0)
        h.set(1)
        h.set(2)
        h.undo()
        #expect(h.current == 1)
        h.reset()
        #expect(h.current == 0)
        #expect(h.canUndo)
        h.undo()
        #expect(h.current == 1)
    }

    @Test func everyCollageTemplateHasCells() {
        #expect(CollageTemplate.twoByTwo.cellCount == 4)
        #expect(CollageTemplate.allCases.allSatisfy { $0.cellCount > 0 })
    }
}
