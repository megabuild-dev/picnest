import CoreGraphics
import Foundation
import PicnestCore
import Testing
@testable import Picnest

@MainActor
struct LayoutEditorViewModelTests {
    /// Holds what the view model sends out, and the answers of the fake save panel.
    @MainActor final class Spy {
        var drafts: [LayoutDocument?] = []
        var closes = 0
        var destination: URL?
        var suggestions: [(name: String, folder: URL)] = []
        var revealed: [URL] = []
    }

    struct Rig {
        let model: LayoutEditorViewModel
        let spy: Spy
        let temp: TempDir
        let source: URL
        let suite: TestDefaults
    }

    /// `count` real JPEG photos `p1.jpg` … in a source folder, and a view model on a layout of the first `used`.
    private func makeRig(
        count: Int = 6, used: Int? = nil, document: LayoutDocument? = nil, trashed: Set<MediaID> = []
    ) throws -> Rig {
        let temp = try TempDir()
        let source = try temp.folder("Photos")
        let ids = (1...max(count, 1)).map { "p\($0).jpg" }.prefix(count).map { $0 }
        for (i, id) in ids.enumerated() {
            try writeTestJPEG(
                to: source.appending(path: id), red: CGFloat(i) / 10, green: 0.5, blue: 0.2, size: 80, height: 60)
        }
        let spy = Spy()
        let suite = TestDefaults()
        let images = ImageRepository()
        let service = LayoutExportService(thumbnails: ThumbnailService(images: images), images: images)
        let layout = document ?? LayoutDocument(photoIDs: Array(ids.prefix(used ?? count)))
        let photos = ids.map { LayoutPhoto(id: $0, fileName: ($0 as NSString).deletingPathExtension.uppercased() + "é.jpg") }
        let model = LayoutEditorViewModel(
            document: layout,
            sources: [LayoutSourceOption(id: "all", title: "All Photos", photos: photos)],
            startSource: "all", service: service, source: source,
            protected: ProtectedFiles(source: source, mediaIDs: Set(ids), otherPaths: []),
            fileNames: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.fileName) }),
            saveDraft: { spy.drafts.append($0) },
            chooseDestination: { [spy] name, folder, format in
                spy.suggestions.append((name, folder))
                return spy.destination.map { ($0, format) }
            },
            revealURL: { spy.revealed.append($0) },
            onClose: { spy.closes += 1 },
            isAvailable: { !trashed.contains($0) },
            defaults: suite.defaults)
        return Rig(model: model, spy: spy, temp: temp, source: source, suite: suite)
    }

    // MARK: - Undo

    @Test func testSettingChangeIsOneUndoStep() throws {
        let rig = try makeRig()
        let model = rig.model
        #expect(!model.canUndo)
        model.setOrientation(.portrait)
        #expect(model.document.orientation == .portrait && model.canUndo && !model.canRedo)
        model.undo()
        #expect(model.document.orientation == .landscape && !model.canUndo && model.canRedo)
        model.redo()
        #expect(model.document.orientation == .portrait)
    }

    @Test func testSpacingDragIsOneUndoStepAfterEndDrag() throws {
        let model = try makeRig().model
        model.beginDrag()
        model.setSpacing(30)
        model.setSpacing(40)
        model.setSpacing(50)
        model.endDrag()
        #expect(model.document.spacing == 50)
        model.undo()
        #expect(model.document.spacing == 24)
        #expect(!model.canUndo)
    }

    @Test func testTitleTypingIsOneUndoStep() async throws {
        let model = try makeRig().model
        model.commitDelay = .milliseconds(10)
        model.setTitle("S")
        model.setTitle("Su")
        model.setTitle("Summer")
        try await waitUntil { !model.hasPendingChange }
        #expect(model.document.title == "Summer")
        model.undo()
        #expect(model.document.title == "")
        #expect(!model.canUndo)
    }

    @Test func testAnotherSettingEndsTheTypingStep() throws {
        let model = try makeRig().model
        model.setTitle("Trip")
        model.setNote("Note")  // a different field: the title step ends first
        model.undo()
        #expect(model.document.note == "" && model.document.title == "Trip")
        model.undo()
        #expect(model.document.title == "")
    }

    // MARK: - Pages and photos

    @Test func testPagesFollowPhotoCount() throws {
        let model = try makeRig(count: 7).model  // 3 × 2 per page
        #expect(model.pages.count == 2)
        #expect(model.pageText == "Page 1 of 2")
        model.step(page: 1)
        #expect(model.pageText == "Page 2 of 2")
        model.step(page: 1)
        #expect(model.pageText == "Page 2 of 2")  // stops at the last page
        model.remove(["p7.jpg", "p6.jpg", "p5.jpg"])
        #expect(model.pageText == "Page 1 of 1")  // the page index stays in range
        #expect(model.countText == "4 photos")
    }

    @Test func testAddDropsRepeatsAndRemoveSelectedRemoves() throws {
        let model = try makeRig(count: 6, used: 3).model
        model.add(["p3.jpg", "p4.jpg", "p5.jpg"], at: nil)  // p3 is in the layout already
        #expect(model.document.photoIDs == ["p1.jpg", "p2.jpg", "p3.jpg", "p4.jpg", "p5.jpg"])
        model.add(["p6.jpg"], at: 0)
        #expect(model.document.photoIDs.first == "p6.jpg")
        model.add(["p6.jpg"], at: 2)  // nothing new: no undo step
        model.undo()
        #expect(model.document.photoIDs.first == "p1.jpg")
        model.selectCell(1)
        model.removeSelected()
        #expect(model.document.photoIDs == ["p1.jpg", "p3.jpg", "p4.jpg", "p5.jpg"])
        #expect(model.selectedCell == 1)  // the cell stays, now with the next photo
    }

    @Test func testMoveReorders() throws {
        let model = try makeRig(count: 4).model
        model.move("p1.jpg", to: 2)
        #expect(model.document.photoIDs == ["p2.jpg", "p3.jpg", "p1.jpg", "p4.jpg"])
        model.swap("p2.jpg", "p4.jpg")
        #expect(model.document.photoIDs == ["p4.jpg", "p3.jpg", "p1.jpg", "p2.jpg"])
        model.undo()
        model.undo()
        #expect(model.document.photoIDs == ["p1.jpg", "p2.jpg", "p3.jpg", "p4.jpg"])
    }

    @Test func testSelectedCellIsDroppedWhenItLeavesTheLayout() throws {
        let model = try makeRig(count: 7).model
        model.selectCell(8)  // an empty cell on page 2
        #expect(model.selectedCell == 8)
        model.setGrid(GridPreset(columns: 2, rows: 3))
        #expect(model.selectedCell == 8)
        model.setKind(.collage)  // a collage has no cell yet
        #expect(model.selectedCell == nil)
    }

    // MARK: - Texts

    @Test func testPaperTextFollowsOrientation() throws {
        let model = try makeRig().model
        #expect(model.paperText == "A4 (297 × 210 mm)")
        model.setOrientation(.portrait)
        #expect(model.paperText == "A4 (210 × 297 mm)")
        #expect(model.spacingText == "24 pt")
    }

    @Test func testCollageUsedText() throws {
        let model = try makeRig(count: 6).model
        #expect(model.usedText == nil)  // a contact sheet uses all photos
        model.setKind(.collage)
        model.setTemplate(.twoByTwo)
        #expect(model.usedText == "Uses 4 of 6 photos")
    }

    // MARK: - Draft

    @Test func testDraftSavesAfterTheDelayAndOnClose() async throws {
        let rig = try makeRig()
        let model = rig.model
        model.draftDelay = .milliseconds(10)
        model.setOrientation(.portrait)
        #expect(rig.spy.drafts.isEmpty)
        try await waitUntil { !rig.spy.drafts.isEmpty }
        #expect(rig.spy.drafts.last??.orientation == .portrait)
        model.draftDelay = .seconds(60)
        model.setPaper(.a3)
        model.requestClose()  // saves at once, with no dialog
        #expect(rig.spy.drafts.last??.paper == .a3)
        #expect(rig.spy.closes == 1)
    }

    // MARK: - Source panel

    @Test func testSourceSearchFiltersTheLeftPanel() throws {
        let model = try makeRig(count: 3).model
        #expect(model.sourcePhotos.count == 3)
        model.searchText = "p2É"  // case and diacritic insensitive
        #expect(model.sourcePhotos.map(\.id) == ["p2.jpg"])
        model.searchText = "  "
        #expect(model.sourcePhotos.count == 3)
        model.searchText = "zzz"
        #expect(model.sourcePhotos.isEmpty)
        #expect(model.sourceOptions.map(\.id) == ["all"])
    }

    // MARK: - Export

    @Test func testExportSuggestsTheTitleAndAUniqueName() async throws {
        let rig = try makeRig()
        let folder = try rig.temp.folder("Out")
        rig.suite.defaults.set(folder.path, forKey: LayoutEditorViewModel.exportFolderKey)
        FileManager.default.createFile(atPath: folder.appending(path: "Summer trip.pdf").path, contents: Data())
        rig.model.setTitle("Summer trip")
        await rig.model.export()
        #expect(rig.spy.suggestions.map(\.name) == ["Summer trip 2.pdf"])
        #expect(rig.spy.suggestions.first?.folder == folder)
    }

    @Test func testExportWritesAndRemembersTheFolder() async throws {
        let rig = try makeRig(count: 7)
        let folder = try rig.temp.folder("Out")
        rig.spy.destination = folder.appending(path: "Sheet.pdf")
        await rig.model.export()
        #expect(rig.model.exportError == nil && !rig.model.isExporting)
        #expect(rig.model.lastExport == [folder.appending(path: "Sheet.pdf")])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Sheet.pdf").path))
        #expect(rig.suite.defaults.string(forKey: LayoutEditorViewModel.exportFolderKey) == folder.path)
        rig.model.revealLastExport()
        #expect(rig.spy.revealed == [folder.appending(path: "Sheet.pdf")])
        #expect(rig.model.savedText == "Saved 1 file.")
    }

    @Test func testExportOverAPhotoShowsTheMessage() async throws {
        let rig = try makeRig()
        let photo = rig.source.appending(path: "p1.jpg")
        let before = try Data(contentsOf: photo)
        rig.spy.destination = photo
        await rig.model.export()
        #expect(rig.model.exportError == CoreErrorMessages.text(for: PhotoExportError.wouldReplaceOriginal))
        #expect(rig.model.lastExport.isEmpty)
        #expect(try Data(contentsOf: photo) == before)
    }

    @Test func testCancelledPanelExportsNothing() async throws {
        let rig = try makeRig()
        rig.spy.destination = nil
        await rig.model.export()
        #expect(rig.spy.suggestions.count == 1)
        #expect(rig.model.lastExport.isEmpty && rig.model.exportError == nil && !rig.model.isExporting)
        #expect(rig.suite.defaults.string(forKey: LayoutEditorViewModel.exportFolderKey) == nil)
    }

    /// Carry-over N1: a photo in the Trash stays in the draft until a rescan. The export leaves it out,
    /// so the export does not fail with "original missing", and the view model reports the count.
    @Test func testExportLeavesOutPhotosInTheTrash() async throws {
        let rig = try makeRig(count: 3, trashed: ["p2.jpg"])
        try FileManager.default.removeItem(at: rig.source.appending(path: "p2.jpg"))  // the file left the folder
        let folder = try rig.temp.folder("Out")
        rig.spy.destination = folder.appending(path: "Sheet.png")
        #expect(rig.model.unavailableCount == 1)
        await rig.model.export()
        #expect(rig.model.exportError == nil)
        #expect(rig.model.lastExport.count == 1)
        #expect(rig.model.document.photoIDs.contains("p2.jpg"))  // the draft keeps it for Put Back
    }

    @Test func testExportWithOnlyTrashedPhotosAsksNothing() async throws {
        let rig = try makeRig(count: 1, trashed: ["p1.jpg"])
        await rig.model.export()
        #expect(rig.spy.suggestions.isEmpty && rig.model.lastExport.isEmpty)
    }

    // MARK: - Preview

    @Test func testPreviewUpdatesAfterAChange() async throws {
        let model = try makeRig().model
        try await waitUntil { model.pageImage != nil }
        let landscape = try #require(model.pageImage).width
        model.setOrientation(.portrait)
        try await waitUntil { model.pageImage.map { $0.width != landscape } ?? false }
        #expect(try #require(model.pageImage).width < landscape)
    }

    @Test func testZoomStaysInRange() throws {
        let model = try makeRig().model
        #expect(model.fitsPage)
        for _ in 0..<30 { model.zoomIn() }
        #expect(model.zoom == 4 && !model.fitsPage)
        for _ in 0..<60 { model.zoomOut() }
        #expect(model.zoom == 0.25)
        model.zoomToFit()
        #expect(model.fitsPage)
        model.togglePreview()
        #expect(model.isPreviewing)
    }

    @Test func testEveryChoiceHasADistinctTitle() {
        #expect(Set(LayoutKind.allCases.map(\.title)).count == LayoutKind.allCases.count)
        #expect(Set(PageOrientation.allCases.map(\.title)).count == PageOrientation.allCases.count)
        #expect(Set(LayoutBackground.allCases.map(\.title)).count == LayoutBackground.allCases.count)
        #expect(Set(ExportResolution.allCases.map(\.title)).count == ExportResolution.allCases.count)
    }
}
