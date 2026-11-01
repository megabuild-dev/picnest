import AppKit
import Foundation
import PicnestCore
import SwiftUI
import Testing
@testable import Picnest

@MainActor
struct EditorEntryTests {
    private let fx: ReviewFixture

    init() throws { fx = try ReviewFixture() }

    private var source: URL { fx.temp.url.appending(path: "Photos") }

    private func extraSession(_ names: [String], trashed: [TrashedPhoto] = []) -> (URL) -> Session {
        { [fx] source in
            var session = fx.makeSession(source: source)
            session.scan = ScanResult(
                media: session.scan.media + names.map { fx.file($0) }, dates: session.scan.dates, skipped: [:])
            session.trashed = trashed
            return session
        }
    }

    /// Holds the answers of the fake save panel.
    @MainActor final class Panel {
        var destination: URL?
        var suggestions: [String] = []
    }

    private func makeModel(
        panel: Panel = Panel(), trashOps: FakeTrashFileOps = FakeTrashFileOps(),
        session: ((URL) -> Session)? = nil, onRescan: @escaping () -> Void = {}
    ) throws -> (model: ReviewViewModel, review: ReviewService) {
        try fx.makeModelAndReview(
            onRescan: onRescan, trashOps: trashOps, session: session,
            chooseExport: { [panel] name, _, format in
                panel.suggestions.append(name)
                return panel.destination.map { ($0, format) }
            })
    }

    // MARK: - Which photos open

    @Test func testCanEditOnlyAReadableImage() throws {
        let trashed = TrashedPhoto(mediaID: "b.jpg", trashPath: "/FakeTrash/b.jpg", time: fx.day(2026, 1, 1))
        let (model, _) = try makeModel(session: { [fx] source in
            var session = fx.makeSession(source: source)
            session.trashed = [trashed]
            return session
        })
        #expect(model.canEdit("a.jpg"))
        #expect(!model.canEdit("g.mov"))  // a video
        #expect(!model.canEdit("f.jpg"))  // unreadable
        #expect(!model.canEdit("b.jpg"))  // in the Trash
        #expect(!model.canEdit("missing.jpg"))
        model.selectedItem = .recentlyDeleted
        #expect(!model.canEdit("a.jpg"))
    }

    @Test func testCanEditIsOffWhileFilesMove() async throws {
        let ops = FakeTrashFileOps()
        let (model, review) = try makeModel(trashOps: ops)
        #expect(model.canEdit("a.jpg"))
        ops.trashGate.hold()
        model.click("b.jpg", modifiers: [])
        let run = Task { await model.trashSelection() }
        try await ops.trashGate.untilWaiting()
        #expect(!model.canEdit("a.jpg"))
        model.openEditor("a.jpg")
        #expect(model.editor == nil)
        ops.trashGate.release()
        await run.value
        await review.settled()
        #expect(model.canEdit("a.jpg"))
    }

    @Test func testOpenEditorUsesTheSelectionAsTheSet() throws {
        let (model, _) = try makeModel()
        model.click("g.mov", modifiers: [])  // a video: not in the set
        model.click("c.jpg", modifiers: .command)
        model.click("a.jpg", modifiers: .command)
        model.openEditor()
        let editor = try #require(model.editor)
        let expected = model.visibleIDs.filter { ["a.jpg", "c.jpg"].contains($0) }
        #expect(editor.allPhotos.map(\.id) == expected)
        #expect(editor.current.id == "a.jpg")  // the anchor: the last click
        #expect(editor.current.url == source.appending(path: "a.jpg"))
        #expect(editor.current.fileName == "a.jpg")
    }

    @Test func testOpenEditorWithOneSelectedUsesTheVisiblePhotos() throws {
        let (model, _) = try makeModel()
        model.click("c.jpg", modifiers: [])
        let images = model.visibleIDs.filter { model.canEdit($0) }
        model.openEditor()
        let editor = try #require(model.editor)
        #expect(editor.allPhotos.map(\.id) == images)
        #expect(!images.contains("g.mov") && !images.contains("f.jpg") && images.count == 6)
        #expect(editor.current.id == "c.jpg")
        model.closeEditor()
        model.openEditor("e.jpg")  // a given id wins over the anchor
        #expect(model.editor?.current.id == "e.jpg")
    }

    // MARK: - Editing state

    @Test func testEditingTurnsOffSortRescanDoneAndStartOver() throws {
        var rescans = 0
        let (model, _) = try makeModel(onRescan: { rescans += 1 })
        #expect(model.canSortOrRescan && model.canDone && model.canStartOver && !model.isEditing)
        model.openEditor("a.jpg")
        #expect(model.isEditing)
        #expect(!model.canSortOrRescan && !model.canDone && !model.canStartOver)
        model.rescan()
        model.requestStartOver()
        model.done()
        #expect(rescans == 0 && !model.isConfirmingStartOver)
        #expect(!model.canEdit("b.jpg"))  // no second editor
        model.closeEditor()
        #expect(!model.isEditing && model.canSortOrRescan && model.canDone && model.canStartOver)
    }

    @Test func testCloseEditorKeepsTheSelection() throws {
        let (model, _) = try makeModel()
        model.click("a.jpg", modifiers: [])
        model.click("b.jpg", modifiers: .command)
        model.openEditor()
        #expect(model.editor != nil)
        model.editor?.requestClose()  // no changes: the editor calls onClose
        #expect(model.editor == nil)
        #expect(model.selection == ["a.jpg", "b.jpg"] && model.anchor == "b.jpg")
    }

    @Test func testSidebarChangeWhileEditingAsksToClose() throws {
        let (model, _) = try makeModel()
        model.openEditor("a.jpg")
        let editor = try #require(model.editor)
        editor.rotate(clockwise: true)
        model.selectedItem = .videos
        #expect(model.selectedItem == .all)
        #expect(editor.isConfirmingDiscard && model.editor === editor)
        editor.confirmDiscard()
        #expect(model.editor == nil && model.selectedItem == .videos)
    }

    @Test func testSidebarChangeWithoutEditsClosesAtOnce() throws {
        let (model, _) = try makeModel()
        model.selectedItem = .all
        model.openEditor("a.jpg")
        model.selectedItem = .dontMove
        #expect(model.editor == nil && model.selectedItem == .dontMove)
    }

    // MARK: - Protected files

    @Test func testProtectedFilesHoldEveryPhoto() async throws {
        let ops = FakeTrashFileOps()
        let panel = Panel()
        let (model, review) = try makeModel(
            panel: panel, trashOps: ops, session: extraSession(["Ảnh_01.jpg"]))
        try writeTestJPEG(to: source.appending(path: "a.jpg"), red: 0.5, green: 0.5, blue: 0.5, size: 8)
        // Trash b.jpg, so its record holds a trash path.
        model.click("b.jpg", modifiers: [])
        await model.trashSelection()
        await review.settled()
        let trashPath = try #require(review.session.trashed.first?.trashPath)
        model.openEditor("a.jpg")
        let editor = try #require(model.editor)

        let nfd = "Ảnh_01.jpg".decomposedStringWithCanonicalMapping.uppercased()
        for protectedURL in [
            source.appending(path: "c.jpg"),  // a photo of the session
            source.appending(path: nfd),  // the NFD and upper-case name of a photo
            URL(filePath: trashPath),  // a trashed photo
        ] {
            panel.destination = protectedURL
            await editor.export()
            #expect(editor.exportError == CoreErrorMessages.text(for: PhotoExportError.wouldReplaceOriginal),
                    "\(protectedURL.lastPathComponent)")
            #expect(editor.lastExport == nil)
        }
        panel.destination = source.appending(path: "brand new.jpg")
        await editor.export()
        #expect(editor.exportError == nil && editor.lastExport == source.appending(path: "brand new.jpg"))
    }

    // MARK: - Undo routing

    @Test func testUndoRoutingOrder() {
        // Text first.
        #expect(UndoRouting.route(firstResponderIsText: true, editorCanAct: true, reviewCanAct: true) == .text)
        #expect(UndoRouting.route(firstResponderIsText: true, editorCanAct: nil, reviewCanAct: true) == .text)
        // Then the editor, even when the review could act.
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: true, reviewCanAct: true) == .editor)
        // An open editor that cannot act never gives the review.
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: false, reviewCanAct: true) == .nothing)
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: false, reviewCanAct: false) == .nothing)
        // No editor: the review.
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: nil, reviewCanAct: true) == .review)
        #expect(UndoRouting.route(firstResponderIsText: false, editorCanAct: nil, reviewCanAct: false) == .nothing)
    }
}
