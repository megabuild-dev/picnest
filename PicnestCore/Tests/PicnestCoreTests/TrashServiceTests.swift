import Foundation
import Testing
@testable import PicnestCore

/// Tests that use the real Trash move only files with unique names under a `TempDir`, and remove a
/// Trash entry only while they still own it.
@Suite(.serialized)
struct TrashServiceTests {
    @Test func trashMovesFileAndRecordsIt() throws {
        let dir = try TempDir()
        let file = dir.url.appending(path: "trash-\(UUID().uuidString).jpg")
        let bytes = Data((0..<64).map { UInt8($0) })
        try bytes.write(to: file)
        let before = Date()

        let result = TrashService().trash([(id: "a.jpg", url: file)])

        #expect(result.failed.isEmpty)
        let t = try #require(result.done.first)
        let trashURL = URL(filePath: t.trashPath)
        defer { try? FileManager.default.removeItem(at: trashURL) }
        #expect(result.done.count == 1)
        #expect(t.mediaID == "a.jpg")
        #expect(t.time >= before)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: trashURL) == bytes)
        #expect(trashURL.path.contains("/.Trash"))
    }

    @Test func putBackMovesTheFileHome() throws {
        let dir = try TempDir()
        let file = dir.url.appending(path: "back-\(UUID().uuidString).jpg")
        let bytes = Data((0..<64).map { UInt8(255 - $0) })
        try bytes.write(to: file)
        let service = TrashService()
        let t = try #require(service.trash([(id: "a.jpg", url: file)]).done.first)
        let trashURL = URL(filePath: t.trashPath)
        var owned = true  // After a good put back the Trash entry is not the test's any more.
        defer { if owned { try? FileManager.default.removeItem(at: trashURL) } }

        let error = service.putBack(t, to: file)
        if error == nil { owned = false }
        #expect(error == nil)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: trashURL.path))
    }

    @Test func putBackRefusesWhenTrashFileIsGone() {
        let original = URL(filePath: "/Photos/a.jpg")
        let ops = FakeTrashOps()
        let t = TrashedPhoto(mediaID: "a.jpg", trashPath: "/FakeTrash/x/a.jpg", time: Date())
        guard case .cannotPutBack("a.jpg", _)? = TrashService(fileOps: ops).putBack(t, to: original) else {
            Issue.record("expected cannotPutBack"); return
        }
        #expect(!ops.exists(original))
    }

    @Test func putBackNeverOverwrites() {
        let original = URL(filePath: "/Photos/a.jpg")
        let trashURL = URL(filePath: "/FakeTrash/x/a.jpg")
        let ops = FakeTrashOps(files: [original, trashURL])
        let t = TrashedPhoto(mediaID: "a.jpg", trashPath: trashURL.path, time: Date())
        guard case .cannotPutBack("a.jpg", _)? = TrashService(fileOps: ops).putBack(t, to: original) else {
            Issue.record("expected cannotPutBack"); return
        }
        #expect(ops.exists(original))
        #expect(ops.exists(trashURL))
    }

    @Test func trashWithoutResultingURLIsTrashedWithEmptyPath() {
        let a = URL(filePath: "/Photos/a.jpg")
        let ops = FakeTrashOps(files: [a], noTrashURL: ["a.jpg"])
        let service = TrashService(fileOps: ops)
        let result = service.trash([(id: "a.jpg", url: a)])
        #expect(result.failed.isEmpty)
        let t = result.done.first
        #expect(t?.trashPath == "")
        #expect(t.flatMap { service.putBack($0, to: a) } == .cannotPutBack("a.jpg", TrashService.unknownReason))
        #expect(!ops.exists(a))
    }

    /// Review Focus 3: a volume with no Trash. The file stays; nothing is deleted.
    @Test func trashFailureReportsEachItem() {
        let a = URL(filePath: "/Photos/a.jpg"), b = URL(filePath: "/Photos/b.jpg")
        let ops = FakeTrashOps(files: [a, b], failTrash: ["b.jpg"])
        let result = TrashService(fileOps: ops).trash([(id: "a.jpg", url: a), (id: "b.jpg", url: b)])
        #expect(result.done.map(\.mediaID) == ["a.jpg"])
        #expect(result.failed == [.cannotTrash("b.jpg", "The volume has no Trash.")])
        #expect(!ops.exists(a))
        #expect(ops.exists(b))
    }

    /// The text of the spec 14 and spec 7.4 messages.
    @Test func errorMessagesUseTheSpecText() {
        #expect(TrashError.cannotTrash("a.jpg", "no Trash").message == "The photo could not be moved to the Trash: no Trash.")
        #expect(TrashError.cannotPutBack("a.jpg", "gone").message == "The photo could not be put back: gone.")
        // A reason that ends with a period does not give 2 periods.
        #expect(TrashError.cannotTrash("a.jpg", "No Trash.").message == "The photo could not be moved to the Trash: No Trash.")
    }
}
