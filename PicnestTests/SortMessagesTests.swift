import Foundation
import PicnestCore
import Testing

@testable import Picnest

struct SortMessagesTests {
    // These tests read English texts. They rely on the `-AppleLanguages (en)` argument of the Picnest scheme.

    /// Each `SortError` case has its key in the catalog and gives its exact English text, placeholders filled.
    @Test func testCatalogHasKeyForEachSortError() throws {
        let url = URL(filePath: "/tmp/a.jpg")
        let many = [url, URL(filePath: "/tmp/b.jpg"), URL(filePath: "/tmp/c.jpg"), URL(filePath: "/tmp/d.jpg")]
        let cases: [(error: SortError, key: String, text: String)] = [
            (.unfinishedLastSort, "The last sort did not finish. Click Undo Last Sort first.",
             "The last sort did not finish. Click Undo Last Sort first."),
            (.changedSinceScan([]), "Some photos changed since the scan. Click Rescan, then sort again.",
             "Some photos changed since the scan. Click Rescan, then sort again."),
            (.destinationExists([]), "Some files already exist in the destination. Choose another destination.",
             "Some files already exist in the destination. Choose another destination."),
            (.sizeMismatch(url), "A copy did not match its original. The original was kept.",
             "A copy did not match its original. The original was kept."),
            (.stopped, "The sort stopped.", "The sort stopped."),
            (.undoConflicts([url]), "Some files could not be put back. They are still in the sorted folder: %@.",
             "Some files could not be put back. They are still in the sorted folder: a.jpg."),
            (.undoConflicts(many), "Some files could not be put back. They are still in the sorted folder: %@…",
             "Some files could not be put back. They are still in the sorted folder: a.jpg, b.jpg, c.jpg…"),
            (.nothingToUndo, "There is no sort to undo.", "There is no sort to undo."),
            (.busy, "Another sort is still running. Try again when it stops.",
             "Another sort is still running. Try again when it stops."),
            (.movedAfterUnfinishedSort(oldPath: "/old"),
             "This folder moved after a sort that did not finish. Move it back to %@, then click Undo Last Sort.",
             "This folder moved after a sort that did not finish. Move it back to /old, then click Undo Last Sort."),
        ]
        let strings = try CatalogTests.load().strings
        for (error, key, text) in cases {
            #expect(strings[key] != nil, "No catalog key: \(key)")
            #expect(SortMessages.text(for: error) == text)
        }
    }

    /// `String(localized:)` with a count picks `one` or `other` from the catalog. The number follows the locale.
    @Test func testPhotoCountPlurals() {
        let en = Locale(identifier: "en_US")
        #expect(CountText.photos(0, locale: en) == "0 photos")
        #expect(CountText.photos(1, locale: en) == "1 photo")
        #expect(CountText.photos(1000, locale: en) == "1,000 photos")
    }

    /// Each `FolderError` case of the core gives its English text, and the catalog has its key.
    @Test func testFolderErrorMessages() throws {
        let strings = try CatalogTests.load().strings
        let renamed = FolderError.renameFailed(from: "A", to: "B", reason: "No access")
        #expect(CoreErrorMessages.text(for: renamed) == "The folder \"A\" could not be renamed to \"B\": No access")
        #expect(CoreErrorMessages.text(for: FolderError.folderKept("A", otherFiles: 1))
            == "The folder \"A\" stays, because it holds 1 file that were not in this category.")
        #expect(CoreErrorMessages.text(for: FolderError.folderKept("A", otherFiles: 2))
            == "The folder \"A\" stays, because it holds 2 files that were not in this category.")
        #expect(CoreErrorMessages.text(for: FolderError.folderNotRemoved("A")) == "The folder \"A\" could not be removed.")
        for key in ["The folder \"%@\" could not be renamed to \"%@\": %@",
                    "The folder \"%@\" stays, because it holds %@ that were not in this category.",
                    "The folder \"%@\" could not be removed."] {
            #expect(strings[key] != nil, "No catalog key: \(key)")
        }
    }
}
