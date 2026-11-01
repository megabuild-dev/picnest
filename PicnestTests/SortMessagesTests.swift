import Foundation
import PicnestCore
import Testing

@testable import Picnest

struct SortMessagesTests {
    @Test func testSortMessageStoppedIsInCatalog() throws {
        #expect(SortMessages.text(for: SortError.stopped) == "The sort stopped.")
        #expect(try CatalogTests.load().strings["The sort stopped."] != nil)
    }

    /// Each `SortError` case has its key in the catalog, and the key shows in the text in `en`.
    @Test func testCatalogHasKeyForEachSortError() throws {
        let url = URL(filePath: "/tmp/a.jpg")
        let cases: [(SortError, key: String)] = [
            (.unfinishedLastSort, "The last sort did not finish. Click Undo Last Sort first."),
            (.changedSinceScan([]), "Some photos changed since the scan. Click Rescan, then sort again."),
            (.destinationExists([]), "Some files already exist in the destination. Choose another destination."),
            (.sizeMismatch(url), "A copy did not match its original. The original was kept."),
            (.stopped, "The sort stopped."),
            (.undoConflicts([url]), "Some files could not be put back. They are still in the sorted folder: %@."),
            (.undoConflicts([url, url, url, url]), "Some files could not be put back. They are still in the sorted folder: %@…"),
            (.nothingToUndo, "There is no sort to undo."),
            (.busy, "Another sort is still running. Try again when it stops."),
            (.movedAfterUnfinishedSort(oldPath: "/old"),
             "This folder moved after a sort that did not finish. Move it back to %@, then click Undo Last Sort."),
        ]
        let strings = try CatalogTests.load().strings
        for (error, key) in cases {
            #expect(strings[key] != nil, "No catalog key: \(key)")
            let text = SortMessages.text(for: error)
            #expect(!text.isEmpty && !text.contains("%@"))
        }
    }

    /// `String(localized:)` with a count picks `one` or `other` from the catalog. The number follows the locale.
    @Test func testPhotoCountPlurals() {
        let en = Locale(identifier: "en_US")
        #expect(CountText.photos(0, locale: en) == "0 photos")
        #expect(CountText.photos(1, locale: en) == "1 photo")
        #expect(CountText.photos(1000, locale: en) == "1,000 photos")
    }
}
