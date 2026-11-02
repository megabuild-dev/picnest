import CoreGraphics
import Foundation
import PicnestCore
import Testing
@testable import Picnest

@MainActor
struct PhotoEditorViewModelTests {
    private let temp: TempDir
    private let folder: URL
    private let service: PhotoEditService

    init() throws {
        temp = try TempDir()
        folder = try temp.folder("Photos")
        let images = ImageRepository()
        service = PhotoEditService(thumbnails: ThumbnailService(images: images), images: images)
    }

    private struct Fixture {
        let model: PhotoEditorViewModel
        let panel: Panel
        var closed: Closed
        /// The ids that the photo editor reads as protected at write time.
        let protect: Protect
    }

    @MainActor final class Protect { var ids: Set<MediaID> = [] }

    /// Records the calls of the fake save panel.
    @MainActor final class Panel {
        var suggestions: [String] = []
        var answer: ((String, URL) -> URL?)?
        var revealed: [URL] = []
        /// While true, the fake save panel waits.
        var holds = false
    }

    @MainActor final class Closed { var count = 0; var cancels = 0 }

    /// 3 landscape photos a.jpg, b.jpg, c.jpg (40 × 20 pixels).
    private func makeModel(
        names: [String] = ["a.jpg", "b.jpg", "c.jpg"], start: String? = nil, protectedIDs: Set<MediaID> = [],
        portrait: Set<String> = [], storedSize: PixelSize? = nil
    ) throws -> Fixture {
        var photos: [EditorPhoto] = []
        for name in names {
            let url = folder.appending(path: name)
            try writeTestJPEG(to: url, red: 0.8, green: 0.2, blue: 0.1,
                              size: portrait.contains(name) ? 20 : 40, height: portrait.contains(name) ? 40 : 20)
            photos.append(EditorPhoto(id: name, url: url, fileName: name))
        }
        let panel = Panel()
        let closed = Closed()
        let protect = Protect()
        protect.ids = Set(names).union(protectedIDs)
        let model = PhotoEditorViewModel(
            photos: photos, start: start ?? names[0], service: service,
            protected: { [folder] in ProtectedFiles(source: folder, mediaIDs: protect.ids, otherPaths: []) },
            chooseDestination: { [panel, folder] name, _, format in
                panel.suggestions.append(name)
                while panel.holds { await Task.yield() }
                guard let answer = panel.answer, let url = answer(name, folder) else { return nil }
                return (url, format)
            },
            revealURL: { [panel] in panel.revealed.append($0) },
            onClose: { [closed] in closed.count += 1 },
            onCancelClose: { [closed] in closed.cancels += 1 },
            readSize: { _ in storedSize })
        return Fixture(model: model, panel: panel, closed: closed, protect: protect)
    }

    // MARK: - History

    @Test func testRotateIsOneUndoStep() throws {
        let m = try makeModel().model
        m.rotate(clockwise: true)
        #expect(m.edit.quarterTurns == 1)
        #expect(m.canUndo && m.hasChanges)
        m.undo()
        #expect(m.edit.isOriginal && !m.canUndo && m.canRedo && !m.hasChanges)
    }

    @Test func testSliderDragIsOneUndoStepAfterEndDrag() throws {
        let m = try makeModel().model
        for v in [5.0, 10, 15] { m.setStraighten(v) }
        m.endDrag()
        #expect(m.edit.straighten == 15)
        m.undo()
        #expect(m.edit.straighten == 0 && !m.canUndo)
    }

    @Test func testResetThenUndoBringsTheEditBack() throws {
        let m = try makeModel().model
        m.rotate(clockwise: true)
        m.flip(horizontal: true)
        let edited = m.edit
        m.reset()
        #expect(m.edit.isOriginal)
        m.undo()
        #expect(m.edit == edited)
    }

    @Test func testRedoAfterUndo() throws {
        let m = try makeModel().model
        m.flip(horizontal: false)
        let edited = m.edit
        m.undo()
        m.redo()
        #expect(m.edit == edited && !m.canRedo)
    }

    @Test func testSquareAspectFitsTheCrop() async throws {
        let m = try makeModel().model
        try await waitUntil { m.previewImage != nil }
        m.setAspect(.square)
        #expect(m.edit.aspect == .square)
        // The photo is 2:1, so a square is half of the width and the full height.
        #expect(abs(m.edit.crop.width - 0.5) < 0.001 && abs(m.edit.crop.height - 1) < 0.001)
    }

    // MARK: - Photos and closing

    @Test func testStepWithChangesAsksBeforeDiscard() throws {
        let m = try makeModel().model
        m.rotate(clockwise: true)
        m.step(by: 1)
        #expect(m.isConfirmingDiscard && m.current.id == "a.jpg")
        m.confirmDiscard()
        #expect(m.current.id == "b.jpg" && m.edit == .original && !m.isConfirmingDiscard)
    }

    @Test func testStepWithoutChangesMovesAtOnce() throws {
        let m = try makeModel().model
        m.step(by: 1)
        #expect(m.current.id == "b.jpg" && !m.isConfirmingDiscard)
        m.step(by: -1)
        m.step(by: -1)  // before the first photo: stays
        #expect(m.current.id == "a.jpg")
    }

    @Test func testPositionText() throws {
        let m = try makeModel(start: "b.jpg").model
        #expect(m.positionText == "2 of 3")
    }

    @Test func testCloseWithChangesAsks() throws {
        let fx = try makeModel()
        fx.model.flip(horizontal: true)
        fx.model.requestClose()
        #expect(fx.model.isConfirmingDiscard && fx.closed.count == 0)
        fx.model.confirmDiscard()
        #expect(fx.closed.count == 1)
    }

    @Test func testCloseWithoutChangesCallsOnClose() throws {
        let fx = try makeModel()
        fx.model.requestClose()
        #expect(fx.closed.count == 1 && !fx.model.isConfirmingDiscard)
    }

    // MARK: - Export

    @Test func testSuggestedNameIsUniqueInTheFolder() async throws {
        let fx = try makeModel()
        try Data([1]).write(to: folder.appending(path: "a edited.jpg"))
        await fx.model.export()
        #expect(fx.panel.suggestions == ["a edited 2.jpg"])
    }

    @Test func testCancelledPanelExportsNothing() async throws {
        let fx = try makeModel()
        fx.model.rotate(clockwise: true)
        await fx.model.export()
        #expect(fx.model.lastExport == nil && fx.model.exportError == nil && !fx.model.isExporting)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "a edited.jpg").path))
    }

    @Test func testExportOverTheOriginalShowsTheMessage() async throws {
        let fx = try makeModel()
        let original = folder.appending(path: "a.jpg")
        let before = try Data(contentsOf: original)
        fx.panel.answer = { _, folder in folder.appending(path: "a.jpg") }
        fx.model.rotate(clockwise: true)
        await fx.model.export()
        #expect(fx.model.exportError
                == CoreErrorMessages.text(for: PhotoExportError.wouldReplaceOriginal))
        #expect(fx.model.lastExport == nil)
        #expect(try Data(contentsOf: original) == before)
    }

    @Test func testExportKeepsTheEditAndSetsLastExport() async throws {
        let fx = try makeModel()
        fx.panel.answer = { name, folder in folder.appending(path: name) }
        fx.model.rotate(clockwise: true)
        let edited = fx.model.edit
        await fx.model.export()
        let expected = folder.appending(path: "a edited.jpg")
        #expect(fx.model.lastExport == expected)
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(fx.model.edit == edited && fx.model.exportError == nil)
        #expect(fx.model.savedText == "Saved “a edited.jpg”.")
        fx.model.revealLastExport()
        #expect(fx.panel.revealed == [expected])
    }

    /// Final review C1: a photo that moved while the panel was open is protected at write time.
    @Test func testProtectedSetIsRebuiltAfterThePanelReturns() async throws {
        let fx = try makeModel()
        let moved = folder.appending(path: "moved.jpg")
        try Data([7, 7, 7]).write(to: moved)
        fx.panel.answer = { [protect = fx.protect] _, _ in
            protect.ids.insert("moved.jpg")  // Done moved a photo here while the panel was open
            return moved
        }
        fx.model.rotate(clockwise: true)
        await fx.model.export()
        #expect(fx.model.exportError == CoreErrorMessages.text(for: PhotoExportError.wouldReplaceOriginal))
        #expect(try Data(contentsOf: moved) == Data([7, 7, 7]))
    }

    /// Final review C1: Back, Esc, and a sidebar change cannot close the editor while the panel is open.
    @Test func testCloseIsRefusedWhileThePanelIsOpen() async throws {
        let fx = try makeModel()
        fx.panel.holds = true
        let export = Task { await fx.model.export() }
        try await waitUntil { fx.model.isExporting }
        fx.model.requestClose()
        #expect(fx.closed.count == 0 && fx.closed.cancels == 1 && !fx.model.isConfirmingDiscard)
        fx.model.rotate(clockwise: true)
        fx.model.requestClose()
        #expect(fx.closed.count == 0 && !fx.model.isConfirmingDiscard)
        fx.panel.holds = false
        await export.value
        fx.model.reset()
        fx.model.requestClose()
        #expect(fx.closed.count == 1)
    }

    @Test func testSecondExportClickDoesNotOpenASecondPanel() async throws {
        let fx = try makeModel()
        fx.panel.holds = true
        let first = Task { await fx.model.export() }
        try await waitUntil { fx.model.isExporting }
        await fx.model.export()
        #expect(fx.panel.suggestions.count == 1)
        fx.panel.holds = false
        await first.value
        #expect(!fx.model.isExporting)
    }

    // MARK: - Preview

    @Test func testPreviewUpdatesAfterAnEdit() async throws {
        let m = try makeModel().model
        try await waitUntil { m.previewImage != nil }
        let before = try #require(m.previewImage).width
        m.rotate(clockwise: true)
        try await waitUntil { m.previewImage.map { $0.width != before } == true }
        #expect(m.previewImage?.width == 20)
        m.isShowingOriginal = true
        try await waitUntil { m.previewImage?.width == before }
    }

    // MARK: - Fix round 1

    @Test func testCancelDiscardDropsTheWaitingAction() throws {
        let fx = try makeModel()
        fx.model.rotate(clockwise: true)
        fx.model.step(by: 1)
        #expect(fx.model.isConfirmingDiscard)
        fx.model.cancelDiscard()
        #expect(!fx.model.isConfirmingDiscard && fx.closed.cancels == 1)
        fx.model.confirmDiscard()  // nothing waits now
        #expect(fx.model.current.id == "a.jpg" && fx.model.edit.quarterTurns == 1 && fx.closed.count == 0)
    }

    @Test func testDragCropIsOneUndoStep() throws {
        let m = try makeModel().model
        m.setAspect(.freeform)
        m.dragCrop(.right, dx: -0.25, dy: 0)
        m.dragCrop(.right, dx: -0.5, dy: 0)  // the whole translation since the start
        #expect(abs(m.edit.crop.width - 0.5) < 0.001 && abs(m.edit.crop.x) < 0.001)
        m.endDrag()
        m.undo()
        #expect(m.edit.crop == .full && m.edit.aspect == .freeform)
        m.dragCrop(.move, dx: 0.5, dy: 0.5)  // a full-size crop cannot move
        #expect(m.edit.crop == .full)
    }

    @Test func testUndoMidDragDropsTheDrag() throws {
        let m = try makeModel().model
        m.setStraighten(10)
        #expect(m.canUndo && m.hasChanges)
        m.undo()
        #expect(m.edit.isOriginal && !m.canUndo && !m.canRedo)
        m.rotate(clockwise: true)
        m.setAdjustment(.contrast, 30)
        m.undo()  // drops the contrast only
        #expect(m.edit.quarterTurns == 1 && m.edit[.contrast] == 0 && m.canUndo)
    }

    @Test func testAspectSetBeforeThePreviewLoadsFitsTheCropAfterwards() async throws {
        let m = try makeModel().model
        m.setAspect(.square)  // the base preview is not loaded yet
        try await waitUntil { m.previewImage != nil }
        #expect(abs(m.edit.crop.width - 0.5) < 0.001 && abs(m.edit.crop.height - 1) < 0.001)
        m.undo()  // 1 step for the aspect and its fit
        #expect(m.edit.isOriginal && !m.canUndo)
    }

    @Test func testOnlyTheLatestEditReachesThePreview() async throws {
        let m = try makeModel().model
        try await waitUntil { m.previewImage != nil }
        for _ in 0..<5 {
            m.rotate(clockwise: true)  // 40x20 -> 20x40 -> ...
        }
        // 5 turns: a portrait frame. Older results must not replace it.
        try await waitUntil { m.previewImage?.width == 20 }
        try await Task.sleep(for: .milliseconds(150))
        #expect(m.previewImage?.width == 20 && m.previewImage?.height == 40)
    }

    @Test func testPreviewOfAnOldPhotoNeverShowsOnTheNewOne() async throws {
        let m = try makeModel(portrait: ["b.jpg"]).model
        m.step(by: 1)  // at once, while a.jpg loads
        try await waitUntil { m.previewImage != nil }
        try await Task.sleep(for: .milliseconds(150))
        #expect(m.current.id == "b.jpg" && m.previewImage?.width == 20 && m.previewImage?.height == 40)
    }

    // MARK: - Screen state

    @Test func testOutputSizeFollowsTheCropAndTheTurns() async throws {
        let m = try makeModel(storedSize: PixelSize(width: 4000, height: 2000)).model
        try await waitUntil { m.previewImage != nil && !m.outputSizeText.isEmpty }
        #expect(m.outputSizeText == "4000 × 2000")
        m.setAspect(.square)
        #expect(m.outputSizeText == "2000 × 2000")
        m.rotate(clockwise: true)
        #expect(m.outputSizeText == "2000 × 2000")
    }

    @Test func testOutputSizeUsesTheUprightOrientationOfThePreview() async throws {
        // The file stores 4000 × 2000, but the preview is upright and portrait (an EXIF turn).
        let m = try makeModel(names: ["p.jpg"], portrait: ["p.jpg"], storedSize: PixelSize(width: 4000, height: 2000)).model
        try await waitUntil { m.previewImage != nil && !m.outputSizeText.isEmpty }
        #expect(m.outputSizeText == "2000 × 4000")
    }

    @Test func testOutputSizeIsEmptyWhenTheFileSizeIsUnknown() throws {
        #expect(try makeModel().model.outputSizeText.isEmpty)
    }

    @Test func testToolDecidesWhatTheCanvasDraws() throws {
        let m = try makeModel().model
        #expect(m.showsCropFrame && m.showsGrid)
        m.tool = .straighten
        #expect(!m.showsCropFrame && m.showsGrid)
        m.tool = .rotate
        #expect(!m.showsCropFrame && !m.showsGrid)
        m.tool = .crop
        m.isShowingOriginal = true
        #expect(!m.showsCropFrame && !m.showsGrid)
    }

    @Test func testStatusTextSaysOriginalThenEdited() throws {
        let m = try makeModel().model
        #expect(m.statusText == "a.jpg · Original")
        m.rotate(clockwise: true)
        #expect(m.statusText == "a.jpg · Edited")
    }

    @Test func testValueTexts() {
        #expect(PhotoEditorViewModel.adjustmentText(20) == "+20")
        #expect(PhotoEditorViewModel.adjustmentText(-5) == "-5")
        #expect(PhotoEditorViewModel.adjustmentText(0) == "0")
        #expect(PhotoEditorViewModel.straightenText(10.54, locale: Locale(identifier: "en_US")) == "+10.5°")
        #expect(PhotoEditorViewModel.straightenText(-3, locale: Locale(identifier: "en_US")) == "-3°")
        #expect(PhotoEditorViewModel.straightenText(0, locale: Locale(identifier: "en_US")) == "0°")
    }

    @Test func testStepLimits() throws {
        let m = try makeModel().model
        #expect(!m.canStepBack && m.canStepForward)
        m.step(by: 2)
        #expect(m.canStepBack && !m.canStepForward)
    }

    @Test func testScaleCropGrowsAndShrinksAroundTheCenter() async throws {
        let m = try makeModel().model
        try await waitUntil { m.previewImage != nil }
        m.setAspect(.freeform)
        m.dragCrop(.bottomRight, dx: -0.5, dy: -0.5)
        m.endDrag()
        m.dragCrop(.move, dx: 0.25, dy: 0.25)
        m.endDrag()
        let before = m.edit.crop
        m.scaleCrop(by: 1.05)
        let after = m.edit.crop
        #expect(abs(after.width - before.width * 1.05) < 1e-9)
        #expect(abs((after.x + after.width / 2) - (before.x + before.width / 2)) < 1e-9)
        m.undo()
        #expect(m.edit.crop == before)
    }

    @Test func testScaleCropStaysInsideTheFrameAndKeepsTheRatio() async throws {
        let m = try makeModel().model
        try await waitUntil { m.previewImage != nil }
        m.scaleCrop(by: 1.05)  // the whole frame already
        #expect(m.edit.crop == .full && !m.canUndo)
        m.setAspect(.square)  // 0.5 × 1 of a 2:1 frame
        let before = m.edit.crop
        m.scaleCrop(by: 0.95)
        let c = m.edit.crop
        #expect(c.width < before.width && abs(c.height / c.width - before.height / before.width) < 1e-9)
    }

    @Test func testDragBackAfterAnEdgeClampTracksThePointer() throws {
        let m = try makeModel().model
        m.setAspect(.freeform)
        m.dragCrop(.right, dx: -0.5, dy: 0)
        m.endDrag()  // width 0.5
        m.dragCrop(.move, dx: 0.9, dy: 0)  // clamps at the right edge: x = 0.5
        #expect(abs(m.edit.crop.x - 0.5) < 1e-9)
        m.dragCrop(.move, dx: 0.3, dy: 0)  // back toward the start: follows the pointer at once
        #expect(abs(m.edit.crop.x - 0.3) < 1e-9)
        m.endDrag()
        m.undo()  // the whole move is 1 step
        #expect(abs(m.edit.crop.width - 0.5) < 1e-9 && abs(m.edit.crop.x) < 1e-9)
    }

    @Test func testKeyboardSliderChangesEachBecomeOneUndoStep() async throws {
        let m = try makeModel().model
        m.commitDelay = .milliseconds(20)
        m.setAdjustment(.exposure, 1)
        try await Task.sleep(for: .milliseconds(120))
        m.setAdjustment(.exposure, 2)
        try await Task.sleep(for: .milliseconds(120))
        m.undo()
        #expect(m.edit[.exposure] == 1)
        m.undo()
        #expect(m.edit[.exposure] == 0 && !m.canUndo)
    }

    @Test func testAnotherSliderCommitsThePendingChange() throws {
        let m = try makeModel().model
        m.setAdjustment(.exposure, 10)
        m.setStraighten(5)  // a different slider: the exposure step closes
        m.endDrag()
        m.undo()
        #expect(m.edit[.exposure] == 10 && m.edit.straighten == 0)
    }

    @Test func testMouseSliderDragWaitsForEndDrag() async throws {
        let m = try makeModel().model
        m.commitDelay = .milliseconds(20)
        m.beginDrag()
        m.setStraighten(5)
        try await Task.sleep(for: .milliseconds(120))
        m.setStraighten(9)
        m.endDrag()
        m.undo()
        #expect(m.edit.isOriginal)
    }
}
