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
        var cancels = 0
        var destination: URL?
        var suggestions: [(name: String, folder: URL)] = []
        var revealed: [URL] = []
        /// While true, the fake save panel waits.
        var holdsPanel = false
        /// The ids that the editor reads as protected at write time.
        var protectedIDs: Set<MediaID> = []
        /// Runs when the fake save panel opens.
        var onPanel: (() -> Void)?
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
        spy.protectedIDs = Set(ids)
        let suite = TestDefaults()
        let images = ImageRepository()
        let service = LayoutExportService(thumbnails: ThumbnailService(images: images), images: images)
        let layout = document ?? LayoutDocument(photoIDs: Array(ids.prefix(used ?? count)))
        let photos = ids.map { LayoutPhoto(id: $0, fileName: ($0 as NSString).deletingPathExtension.uppercased() + "é.jpg") }
        let model = LayoutEditorViewModel(
            document: layout,
            sources: [LayoutSourceOption(id: "all", title: "All Photos", photos: photos)],
            startSource: "all", service: service, source: source,
            protected: { [spy] in ProtectedFiles(source: source, mediaIDs: spy.protectedIDs, otherPaths: []) },
            fileNames: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.fileName) }),
            saveDraft: { spy.drafts.append($0) },
            chooseDestination: { [spy] name, folder, format in
                spy.suggestions.append((name, folder))
                spy.onPanel?()
                while spy.holdsPanel { await Task.yield() }
                return spy.destination.map { ($0, format) }
            },
            revealURL: { spy.revealed.append($0) },
            onClose: { spy.closes += 1 },
            onCancelClose: { spy.cancels += 1 },
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
        model.setKind(.collage)  // cell 8 is not in the 4 cells of the template
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

    @Test func testCanExportNeedsAPhotoThatIsNotInTheTrash() throws {
        let allTrashed = try makeRig(count: 2, trashed: ["p1.jpg", "p2.jpg"]).model
        #expect(!allTrashed.canExport)
        let someTrashed = try makeRig(count: 2, trashed: ["p1.jpg"]).model
        #expect(someTrashed.canExport)
        #expect(try !makeRig(count: 2, used: 0).model.canExport)
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

    @Test func testZoomFollowsTheRealScale() throws {
        let model = try makeRig().model  // A4 landscape 841.9 × 595.3 pt in an 800 × 600 area
        model.canvasWidth = 800
        model.canvasHeight = 600
        let fit = model.fitScale
        #expect(abs(fit - 800 / 841.8898) < 1e-6)
        #expect(model.fitsPage && model.scale == fit && model.zoomText == "95%")
        model.zoomOut()
        #expect(!model.fitsPage && model.scale < fit)  // never bigger than fit
        model.zoomToFit()
        #expect(model.fitsPage && model.scale == fit)
        model.zoomIn()
        #expect(model.scale > fit)
        #expect(abs(model.scale - fit * 1.25) < 1e-9)
        model.zoomToFit()
        model.canvasWidth = 100  // a small area: the fit is under the 25% limit
        model.canvasHeight = 100
        let small = model.fitScale
        #expect(small < 0.25)
        model.zoomOut()
        #expect(model.scale <= small)  // the limit never makes Zoom Out bigger
        model.zoomToFit()
        model.zoomIn()
        #expect(model.scale >= small)
    }

    @Test func testZoomStaysInRange() throws {
        let model = try makeRig().model
        for _ in 0..<30 { model.zoomIn() }
        #expect(model.scale == 4 && model.zoomText == "400%")
        for _ in 0..<60 { model.zoomOut() }
        #expect(model.scale == 0.25 && model.zoomText == "25%")
        model.togglePreview()
        #expect(model.isPreviewing)
    }

    @Test func testStalePreviewResultIsDropped() async throws {
        let model = try makeRig().model
        try await waitUntil { model.pageImage != nil }
        let landscape = try #require(model.pageImage).width
        model.setOrientation(.portrait)
        model.setOrientation(.landscape)  // the portrait render must not replace this one
        for _ in 0..<50 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.pageImage?.width == landscape)
    }

    @Test func testSteppingAPageRefreshesTheImage() async throws {
        let model = try makeRig(count: 7).model
        try await waitUntil { model.pageImage != nil }
        let first = try #require(model.pageImage)
        model.step(page: 1)
        try await waitUntil { model.pageImage !== first }
        #expect(model.pageText == "Page 2 of 2")
    }

    @Test func testInitSavesNothingAndUndoSavesTheDraft() async throws {
        let rig = try makeRig()
        rig.model.draftDelay = .milliseconds(10)
        try await Task.sleep(for: .milliseconds(60))
        #expect(rig.spy.drafts.isEmpty)
        rig.model.setPaper(.a3)
        rig.model.undo()
        try await waitUntil { rig.spy.drafts.last??.paper == .a4 }
    }

    /// Final review C1: a photo that moved while the panel was open is protected at write time.
    @Test func testProtectedSetIsRebuiltAfterThePanelReturns() async throws {
        let rig = try makeRig()
        let moved = rig.source.appending(path: "moved.pdf")
        try Data([7, 7, 7]).write(to: moved)
        rig.spy.destination = moved
        rig.spy.onPanel = { [spy = rig.spy] in spy.protectedIDs.insert("moved.pdf") }
        await rig.model.export()
        #expect(rig.model.exportError == CoreErrorMessages.text(for: PhotoExportError.wouldReplaceOriginal))
        #expect(try Data(contentsOf: moved) == Data([7, 7, 7]))
    }

    /// Final review C1: Back and Esc cannot close the editor while the panel is open or the export runs.
    @Test func testCloseIsRefusedWhileThePanelIsOpen() async throws {
        let rig = try makeRig()
        rig.spy.holdsPanel = true
        let export = Task { await rig.model.export() }
        try await waitUntil { rig.model.isExporting }
        rig.model.requestClose()
        #expect(rig.spy.closes == 0 && rig.spy.cancels == 1)
        rig.spy.holdsPanel = false
        await export.value
        rig.model.requestClose()
        #expect(rig.spy.closes == 1)
    }

    @Test func testSecondExportCallDoesNotOpenASecondPanel() async throws {
        let rig = try makeRig()
        rig.spy.holdsPanel = true
        let first = Task { await rig.model.export() }
        try await waitUntil { rig.model.isExporting }
        await rig.model.export()
        #expect(rig.spy.suggestions.count == 1)
        rig.spy.holdsPanel = false
        await first.value
        #expect(!rig.model.isExporting)
    }

    @Test func testNewExportClearsTheOldError() async throws {
        let rig = try makeRig()
        rig.spy.destination = rig.source.appending(path: "p1.jpg")
        await rig.model.export()
        #expect(rig.model.exportError != nil)
        rig.spy.destination = nil  // the user cancels the panel
        await rig.model.export()
        #expect(rig.model.exportError == nil)
    }

    @Test func testCollageUsedTextFollowsTheTemplate() throws {
        let model = try makeRig(count: 6).model
        model.setKind(.collage)
        model.setTemplate(.twoOverThree)
        #expect(model.usedText == "Uses 5 of 6 photos")
        model.setTemplate(.heroLeft)
        #expect(model.usedText == "Uses 3 of 6 photos")
        #expect(model.pages.count == 1 && model.currentPage.cells.count == 3)
    }

    @Test func testCollageMovePastTheLastCellKeepsThePhotoAndClearsTheSelection() throws {
        let model = try makeRig(count: 6).model
        model.setKind(.collage)
        model.setTemplate(.twoByTwo)  // 4 cells for 6 photos
        let before = model.document.photoIDs
        model.selectCell(1)
        model.movePhoto(at: 1, by: 4)  // index 5 has no cell
        #expect(model.document.photoIDs == [before[0]] + Array(before[2...5]) + [before[1]])
        #expect(Set(model.document.photoIDs) == Set(before))
        #expect(model.selectedCell == nil)
        model.undo()
        #expect(model.document.photoIDs == before)
    }

    @Test func testCollageSelectionKeepsACellAndDropsOneOutsideTheTemplate() throws {
        let model = try makeRig(count: 6).model
        model.setKind(.collage)
        model.setTemplate(.heroLeft)
        model.selectCell(2)
        model.setTemplate(.twoByTwo)
        #expect(model.selectedCell == 2)
        model.setTemplate(.heroLeft)
        model.selectCell(3)  // photo 3 is not in a cell of the template
        #expect(model.selectedCell == nil)
        model.selectCell(2)
        model.setTemplate(.heroTop)
        model.selectCell(3)
        model.moveSelection(by: 5)  // stays at the last cell
        #expect(model.selectedCell == 3)
    }

    @Test func testEveryTemplateHasADistinctTitle() {
        #expect(Set(CollageTemplate.allCases.map(\.title)).count == CollageTemplate.allCases.count)
        #expect(CollageTemplate.allCases.map(\.title) == ["Two by two", "Large left", "Large top", "Two over three"])
    }

    @Test func testUsedTextHasASingularForm() throws {
        let model = try makeRig(count: 1).model
        model.setKind(.collage)
        #expect(model.usedText == "Uses 1 of 1 photo")
    }

    @Test func testEveryChoiceHasADistinctTitle() {
        #expect(Set(LayoutKind.allCases.map(\.title)).count == LayoutKind.allCases.count)
        #expect(Set(PageOrientation.allCases.map(\.title)).count == PageOrientation.allCases.count)
        #expect(Set(LayoutBackground.allCases.map(\.title)).count == LayoutBackground.allCases.count)
        #expect(Set(ExportResolution.allCases.map(\.title)).count == ExportResolution.allCases.count)
    }

    // MARK: - Cells, keys, and drops

    @Test func testCellAtPagePointUsesTheCellFrames() throws {
        let model = try makeRig().model
        let cell = model.currentPage.cells[4]
        let inside = CGPoint(x: cell.frame.x + cell.frame.width / 2, y: cell.frame.y + cell.frame.height / 2)
        #expect(model.cell(atPagePoint: inside) == 4)
        #expect(model.cell(atPagePoint: CGPoint(x: 1, y: 1)) == nil)
    }

    @Test func testArrowKeysSelectAcrossPages() throws {
        let model = try makeRig(count: 7).model
        #expect(model.pages.count == 2)
        model.moveSelection(by: 1)
        #expect(model.selectedCell == 0)
        model.moveSelection(by: -1)
        #expect(model.selectedCell == 0)
        model.selectCell(5)
        model.moveSelection(by: 1)
        #expect(model.selectedCell == 6 && model.pageIndex == 1)
        model.moveSelection(by: 100)
        #expect(model.selectedCell == 11)
        model.selectCell(99)
        #expect(model.selectedCell == nil)
    }

    @Test func testOptionArrowsMoveThePhotoAndTheSelectionFollows() throws {
        let model = try makeRig(count: 3).model
        model.selectCell(1)
        model.moveSelectedPhoto(by: 1)
        #expect(model.document.photoIDs == ["p1.jpg", "p3.jpg", "p2.jpg"] && model.selectedCell == 2)
        model.moveSelectedPhoto(by: 1)
        #expect(model.document.photoIDs == ["p1.jpg", "p3.jpg", "p2.jpg"])
        #expect(model.canMovePhoto(at: 2, by: -1) && !model.canMovePhoto(at: 2, by: 1))
        model.selectCell(4)  // an empty cell: nothing moves
        model.moveSelectedPhoto(by: -1)
        #expect(model.document.photoIDs == ["p1.jpg", "p3.jpg", "p2.jpg"])
    }

    @Test func testDeleteRemovesTheSelectedPhotoAsOneUndoStep() throws {
        let model = try makeRig(count: 3).model
        model.selectCell(0)
        model.removeSelected()
        #expect(model.document.photoIDs == ["p2.jpg", "p3.jpg"])
        model.undo()
        #expect(model.document.photoIDs.count == 3)
        model.removePhoto(at: 9)
        #expect(model.document.photoIDs.count == 3)
    }

    @Test func testDropOnACellInsertsThereAndOnThePageAppends() throws {
        let model = try makeRig(count: 5, used: 3).model
        model.drop(["p4.jpg"], onCell: 1)
        #expect(model.document.photoIDs == ["p1.jpg", "p4.jpg", "p2.jpg", "p3.jpg"])
        model.drop(["p5.jpg"], onCell: nil)
        #expect(model.document.photoIDs.last == "p5.jpg")
        model.undo()
        #expect(model.document.photoIDs.count == 4)
    }

    @Test func testDropOfAHeldPhotoSwapsOrGoesToTheEnd() throws {
        let model = try makeRig(count: 3).model
        model.drop(["p1.jpg"], onCell: 2)
        #expect(model.document.photoIDs == ["p3.jpg", "p2.jpg", "p1.jpg"] && model.selectedCell == 2)
        model.drop(["p3.jpg"], onCell: 5)
        #expect(model.document.photoIDs == ["p2.jpg", "p1.jpg", "p3.jpg"])
        model.drop(["p2.jpg"], onCell: nil)
        model.drop(["p2.jpg"], onCell: 0)
        #expect(model.document.photoIDs == ["p2.jpg", "p1.jpg", "p3.jpg"])
    }

    @Test func testCellLabelsNameThePhotoOrTheEmptyCell() throws {
        let model = try makeRig(count: 2).model
        let cells = model.currentPage.cells
        #expect(model.cellLabel(for: cells[1]) == "Photo 2 of 2, P2é.jpg")
        #expect(model.cellLabel(for: cells[3]) == "Empty cell 4")
    }

    @Test func testEscapeLeavesPreviewBeforeClosing() throws {
        let rig = try makeRig()
        rig.model.togglePreview()
        rig.model.handleEscape()
        #expect(!rig.model.isPreviewing && rig.spy.closes == 0)
        rig.model.handleEscape()
        #expect(rig.spy.closes == 1)
    }

    @Test func testExportOffersTheChosenFormatFirst() async throws {
        let rig = try makeRig()
        rig.spy.destination = nil
        await rig.model.export(startingWith: .png)
        #expect(rig.spy.suggestions.last?.name.hasSuffix(".png") == true)
    }

    @Test func testPaperTextFollowsTheOrientation() {
        #expect(LayoutEditorViewModel.paperText(.a4, orientation: .landscape) == "A4 (297 × 210 mm)")
        #expect(LayoutEditorViewModel.paperText(.a4, orientation: .portrait) == "A4 (210 × 297 mm)")
    }

    @Test func testMoveIsOfferedOnlyInsideTheRange() throws {
        let model = try makeRig(count: 3).model
        #expect(!model.canMovePhoto(at: 0, by: -1) && model.canMovePhoto(at: 0, by: 1))
        #expect(model.canMovePhoto(at: 2, by: -1) && !model.canMovePhoto(at: 2, by: 1))
        #expect(!model.canMovePhoto(at: 4, by: -1))
    }

    @Test func testExportIsOnlyOfferedWithPhotosAndNotWhileRunning() async throws {
        let empty = try makeRig(count: 1, used: 0).model
        #expect(!empty.canExport)
        let rig = try makeRig()
        #expect(rig.model.canExport)
        rig.spy.holdsPanel = true
        let task = Task { await rig.model.export() }
        while !rig.model.isExporting { await Task.yield() }
        #expect(!rig.model.canExport)
        rig.spy.holdsPanel = false
        await task.value
    }
}
