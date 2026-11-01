import Testing
@testable import PicnestCore

@Suite struct PhotoEditTests {
    @Test func originalIsOriginal() {
        #expect(PhotoEdit.original.isOriginal)
        var e = PhotoEdit.original
        e[.exposure] = 5
        #expect(!e.isOriginal)
        e[.exposure] = 0
        #expect(e.isOriginal)
    }

    @Test func adjustmentIsClamped() {
        var e = PhotoEdit.original
        e[.contrast] = 150
        #expect(e[.contrast] == 100)
        e[.contrast] = -150
        #expect(e[.contrast] == -100)
    }

    @Test func straightenIsClamped() {
        var e = PhotoEdit.original
        e.straighten = -60
        #expect(e.straighten == -45)
        e.straighten = 60
        #expect(e.straighten == 45)
    }

    @Test func fourRotationsGiveTheOriginal() {
        var e = PhotoEdit.original
        e.crop = NormalizedRect(x: 0.125, y: 0.25, width: 0.5, height: 0.25)
        let start = e
        for _ in 0..<4 { e.rotate(clockwise: true) }
        #expect(e == start)
        e.rotate(clockwise: true)
        e.rotate(clockwise: false)
        #expect(e == start)
        e.rotate(clockwise: false)
        #expect(e.quarterTurns == 3)
    }

    @Test func rotateMovesTheCrop() {
        var e = PhotoEdit.original
        e.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.25)
        e.rotate(clockwise: true)
        #expect(e.crop == NormalizedRect(x: 0.75, y: 0, width: 0.25, height: 0.5))
        #expect(e.quarterTurns == 1)
    }

    @Test func flipHorizontalMovesTheCrop() {
        var e = PhotoEdit.original
        e.crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        e.flip(horizontal: true)
        #expect(e.flipHorizontal)
        #expect(abs(e.crop.x - 0.4) < 1e-12)
        #expect(e.crop.y == 0.2)
        e.flip(horizontal: false)
        #expect(e.flipVertical)
        #expect(abs(e.crop.y - 0.55) < 1e-12)
    }

    @Test func twoFlipsGiveTheOriginal() {
        var e = PhotoEdit.original
        e.crop = NormalizedRect(x: 0.125, y: 0.25, width: 0.5, height: 0.25)
        let start = e
        e.flip(horizontal: true)
        e.flip(horizontal: true)
        e.flip(horizontal: false)
        e.flip(horizontal: false)
        #expect(e == start)
    }

    @Test func portraitFrameTurnsFourThree() {
        let original = PixelSize(width: 40, height: 30)
        #expect(AspectRatio.fourThree.ratio(frame: PixelSize(width: 30, height: 40), original: original) == 0.75)
        #expect(AspectRatio.fourThree.ratio(frame: PixelSize(width: 40, height: 30), original: original) == 4.0 / 3.0)
        #expect(AspectRatio.freeform.ratio(frame: original, original: original) == nil)
        #expect(AspectRatio.square.ratio(frame: original, original: original) == 1)
        #expect(AspectRatio.original.ratio(frame: PixelSize(width: 30, height: 40), original: original) == 0.75)
    }

    @Test func defaultFormatFollowsTheOriginal() {
        #expect(ExportFormat.defaultFormat(forExtension: "JPG") == .jpeg)
        #expect(ExportFormat.defaultFormat(forExtension: "HEIF") == .heic)
        #expect(ExportFormat.defaultFormat(forExtension: "gif") == .png)
        #expect(ExportFormat.defaultFormat(forExtension: "webp") == .jpeg)
        #expect(ExportFormat.defaultFormat(forExtension: "tiff") == .png)
    }

    private func edit(_ turns: Int) -> PhotoEdit {
        var e = PhotoEdit.original
        e.straighten = Double(turns) / 10
        return e
    }

    @Test func dragIsOneUndoStep() {
        var h = EditHistory()
        for i in 1...10 { h.show(edit(i)) }
        #expect(!h.canUndo)
        h.commit()
        #expect(h.canUndo)
        h.undo()
        #expect(h.current == .original)
        #expect(!h.canUndo)
        #expect(h.canRedo)
        h.redo()
        #expect(h.current == edit(10))
    }

    @Test func commitWithoutChangeAddsNoStep() {
        var h = EditHistory()
        h.commit()
        #expect(!h.canUndo)
        h.set(edit(1))
        h.commit()
        h.undo()
        #expect(h.current == .original)
        #expect(!h.canUndo)
    }

    @Test func resetIsUndoable() {
        var h = EditHistory()
        h.set(edit(3))
        h.reset()
        #expect(h.current == .original)
        h.undo()
        #expect(h.current == edit(3))
    }

    @Test func newStepClearsRedo() {
        var h = EditHistory()
        h.set(edit(1))
        h.undo()
        #expect(h.canRedo)
        h.set(edit(2))
        #expect(!h.canRedo)
    }

    @Test func historyKeepsAtMost100Steps() {
        var h = EditHistory()
        for i in 1...150 { h.set(edit(i)) }
        var steps = 0
        while h.canUndo { h.undo(); steps += 1 }
        #expect(steps == 100)
    }

    @Test func rotateAfterOneFlipTurnsTheOtherWay() {
        var e = PhotoEdit.original
        e.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.25)
        e.flip(horizontal: true)
        #expect(e.crop == NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.25))
        e.rotate(clockwise: true)
        #expect(e.quarterTurns == 3)
        #expect(e.crop == NormalizedRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5))
        e.rotate(clockwise: false)
        #expect(e.quarterTurns == 0)
        #expect(e.crop == NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.25))
    }

    @Test func rotateAfterTwoFlipsTurnsTheSameWay() {
        var e = PhotoEdit.original
        e.flip(horizontal: true)
        e.flip(horizontal: false)
        e.rotate(clockwise: true)
        #expect(e.quarterTurns == 1)
    }

    @Test func fourRotationsGiveTheOriginalInEveryFlipState() {
        for (h, v) in [(false, false), (true, false), (false, true), (true, true)] {
            for cw in [true, false] {
                var e = PhotoEdit.original
                e.crop = NormalizedRect(x: 0.125, y: 0.25, width: 0.5, height: 0.25)
                if h { e.flip(horizontal: true) }
                if v { e.flip(horizontal: false) }
                let start = e
                for _ in 0..<4 { e.rotate(clockwise: cw) }
                #expect(e == start)
            }
        }
    }

    @Test func undoRevertsAPendingShowFirst() {
        var h = EditHistory()
        h.show(edit(5))
        h.undo()
        #expect(h.current == .original)
        #expect(!h.canUndo)
        h.set(edit(1))
        h.show(edit(2))
        h.undo()
        #expect(h.current == edit(1))
        #expect(h.canUndo)
        h.undo()
        #expect(h.current == .original)
    }

    @Test func flipMirrorsTheStraightenAngle() {
        var e = PhotoEdit.original
        e.straighten = 5
        e.flip(horizontal: true)
        #expect(e.straighten == -5)
        e.flip(horizontal: false)
        #expect(e.straighten == 5)
    }

    @Test func flippingTwiceRestoresTheEdit() {
        var e = PhotoEdit.original
        e.straighten = 7
        e.crop = NormalizedRect(x: 0.125, y: 0.25, width: 0.25, height: 0.5)
        let before = e
        e.flip(horizontal: true)
        e.flip(horizontal: true)
        #expect(e == before)
        e.flip(horizontal: false)
        e.flip(horizontal: false)
        #expect(e == before)
    }

    @Test func quarterTurnKeepsTheStraightenAngle() {
        var e = PhotoEdit.original
        e.straighten = 5
        e.rotate(clockwise: true)
        #expect(e.straighten == 5)
        e.rotate(clockwise: false)
        #expect(e.straighten == 5)
    }

    @Test func historyReportsAShownValueThatIsNotCommitted() {
        var h = EditHistory()
        var e = PhotoEdit()
        e.straighten = 5
        h.show(e)
        #expect(h.hasPendingChange && !h.canUndo)
        h.commit()
        #expect(!h.hasPendingChange && h.canUndo)
    }
}
