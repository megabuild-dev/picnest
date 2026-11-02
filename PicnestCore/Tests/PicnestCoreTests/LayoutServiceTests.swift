import Foundation
import Testing
@testable import PicnestCore

@Suite struct LayoutServiceTests {
    private func doc(_ ids: [MediaID]) -> LayoutDocument {
        LayoutDocument.new(photos: ids, title: "T")
    }

    private func session(draft: LayoutDocument?) -> Session {
        Session(sourcePath: "/x", candidateList: .artStudio, categories: [], states: [:],
                scan: ScanResult(media: [], dates: [:], skipped: [:]), sortedAt: nil, layoutDraft: draft)
    }

    @Test func addKeepsOrderWithoutRepeats() {
        var d = doc(["a", "b"])
        #expect(LayoutService.add(["c", "a", "d", "c"], to: &d))
        #expect(d.photoIDs == ["a", "b", "c", "d"])
        #expect(!LayoutService.add(["a"], to: &d))
    }

    @Test func addAtIndexInserts() {
        var d = doc(["a", "b"])
        #expect(LayoutService.add(["x", "y"], to: &d, at: 1))
        #expect(d.photoIDs == ["a", "x", "y", "b"])
        #expect(LayoutService.add(["z"], to: &d, at: 99))
        #expect(d.photoIDs.last == "z")
    }

    @Test func moveAndSwapReorder() {
        var d = doc(["a", "b", "c", "d"])
        #expect(LayoutService.move("a", to: 2, in: &d))
        #expect(d.photoIDs == ["b", "c", "a", "d"])
        #expect(!LayoutService.move("a", to: 2, in: &d))
        #expect(!LayoutService.move("zz", to: 0, in: &d))
        #expect(LayoutService.swap("b", "d", in: &d))
        #expect(d.photoIDs == ["d", "c", "a", "b"])
        #expect(!LayoutService.swap("b", "nope", in: &d))
    }

    @Test func removeDropsIDs() {
        var d = doc(["a", "b", "c"])
        #expect(LayoutService.remove(["b", "q"], from: &d))
        #expect(d.photoIDs == ["a", "c"])
        #expect(!LayoutService.remove(["q"], from: &d))
    }

    @Test func rekeyMovesDraftPhotos() {
        var s = session(draft: doc(["a", "b", "c"]))
        LayoutService.rekey(["a": "A/a", "c": "b"], in: &s)
        #expect(s.layoutDraft?.photoIDs == ["A/a", "b"])
        var none = session(draft: nil)
        LayoutService.rekey(["a": "x"], in: &none)
        #expect(none.layoutDraft == nil)
    }

    @Test func pruneDropsMissingDraftPhotos() {
        var s = session(draft: doc(["a", "b", "c"]))
        LayoutService.prune(keeping: ["a", "c"], in: &s)
        #expect(s.layoutDraft?.photoIDs == ["a", "c"])
    }
}
