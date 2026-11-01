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
    }

    /// Records the calls of the fake save panel.
    @MainActor final class Panel {
        var suggestions: [String] = []
        var answer: ((String, URL) -> URL?)?
        var revealed: [URL] = []
    }

    @MainActor final class Closed { var count = 0 }

    /// 3 landscape photos a.jpg, b.jpg, c.jpg (40 × 20 pixels).
    private func makeModel(
        names: [String] = ["a.jpg", "b.jpg", "c.jpg"], start: String? = nil, protectedIDs: Set<MediaID> = []
    ) throws -> Fixture {
        var photos: [EditorPhoto] = []
        for name in names {
            let url = folder.appending(path: name)
            try writeTestJPEG(to: url, red: 0.8, green: 0.2, blue: 0.1, size: 40, height: 20)
            photos.append(EditorPhoto(id: name, url: url, fileName: name))
        }
        let panel = Panel()
        let closed = Closed()
        let protected = ProtectedFiles(source: folder, mediaIDs: Set(names).union(protectedIDs), otherPaths: [])
        let model = PhotoEditorViewModel(
            photos: photos, start: start ?? names[0], service: service, protected: protected,
            chooseDestination: { [panel, folder] name, _, format in
                panel.suggestions.append(name)
                guard let answer = panel.answer, let url = answer(name, folder) else { return nil }
                return (url, format)
            },
            revealURL: { [panel] in panel.revealed.append($0) },
            onClose: { [closed] in closed.count += 1 })
        return Fixture(model: model, panel: panel, closed: closed)
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
        m.setAdjustment(.exposure, 20)
        m.endDrag()
        #expect(m.edit.straighten == 15)
        m.undo()
        #expect(m.edit.straighten == 0 && m.edit[.exposure] == 0 && !m.canUndo)
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
}
