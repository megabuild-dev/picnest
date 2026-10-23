import Foundation
import Testing
@testable import PicnestCore

struct SortPlannerTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let src = URL(filePath: "/tmp/ps-src", directoryHint: .isDirectory)
    private let dst = URL(filePath: "/tmp/ps-dst", directoryHint: .isDirectory)
    private let food = Category(id: UUID(), displayName: "Food", emoji: "", prompts: [], exampleIDs: [], order: 0)
    private let pets = Category(id: UUID(), displayName: "Pets", emoji: "", prompts: [], exampleIDs: [], order: 1)

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s + "T12:00:00Z")!
    }

    private func media(_ path: String, _ kind: MediaKind = .image) -> MediaFile {
        MediaFile(id: path, relativePath: path, kind: kind, size: 10, modified: date("2024-01-01"))
    }

    private func assignment(_ c: Category, uncertain: Bool = false) -> Assignment {
        Assignment(categoryID: c.id, score: 0.3, secondCategoryID: nil, secondScore: nil, percent: 50, uncertain: uncertain)
    }

    private func session(_ files: [MediaFile], states: [MediaID: PhotoState], dates: [MediaID: String] = [:],
                         categories: [Category]? = nil) -> Session {
        var d: [MediaID: PhotoDate] = [:]
        for (k, v) in dates { d[k] = PhotoDate(date: date(v), source: .exif) }
        return Session(sourcePath: src.path, candidateList: .everyday, categories: categories ?? [food, pets], states: states,
                       scan: ScanResult(media: files, dates: d, skipped: [:]), sortedAt: nil)
    }

    private func opts(dateFolders: Bool = false, rename: Bool = false, choice: NotSureChoice = .acceptBestGuess) -> SortOptions {
        SortOptions(destination: dst, mode: .copy, dateFolders: dateFolders, rename: rename, notSureChoice: choice)
    }

    private func plan(_ s: Session, _ o: SortOptions, existing: @escaping (URL) -> Set<String> = { _ in [] }) throws -> SortPlan {
        try SortPlanner(timeZone: utc).plan(s, source: src, options: o, existingNames: existing)
    }

    private func rel(_ p: SortPlan) -> [String] {
        p.entries.map { String($0.destination.path.dropFirst(dst.path.count + 1)) }
    }

    @Test func noDateFoldersByDefault() throws {
        let s = session([media("IMG_1.jpg")], states: ["IMG_1.jpg": .manual(food.id)])
        #expect(rel(try plan(s, opts())) == ["Food/IMG_1.jpg"])
    }

    @Test func dateFoldersWhenTicked() throws {
        let s = session([media("IMG_1.jpg")], states: ["IMG_1.jpg": .manual(food.id)], dates: ["IMG_1.jpg": "2024-05-12"])
        #expect(rel(try plan(s, opts(dateFolders: true))) == ["Food/2024-05/IMG_1.jpg"])
    }

    @Test func renameFormat() throws {
        let s = session([media("b.jpg"), media("a.JPEG")],
                        states: ["a.JPEG": .manual(food.id), "b.jpg": .manual(food.id)],
                        dates: ["a.JPEG": "2024-05-12", "b.jpg": "2024-05-12"])
        let p = try plan(s, opts(rename: true))
        let byID = Dictionary(uniqueKeysWithValues: p.entries.map { ($0.mediaID, $0.destination.lastPathComponent) })
        #expect(byID["a.JPEG"] == "2024-05-12_Food_001.jpg")
        #expect(byID["b.jpg"] == "2024-05-12_Food_002.jpg")
    }

    @Test func renameUsesUniquedFolderName() throws {
        let a = Category(id: UUID(), displayName: "A/B", emoji: "", prompts: [], exampleIDs: [], order: 0)
        let b = Category(id: UUID(), displayName: "A:B", emoji: "", prompts: [], exampleIDs: [], order: 1)
        let s = session([media("x.jpg"), media("y.jpg")], states: ["x.jpg": .manual(a.id), "y.jpg": .manual(b.id)],
                        dates: ["x.jpg": "2024-05-12", "y.jpg": "2024-05-12"], categories: [a, b])
        let p = try plan(s, opts(rename: true))
        #expect(p.entries.map { $0.destination.lastPathComponent } == ["2024-05-12_A-B_001.jpg", "2024-05-12_A-B 2_001.jpg"])
    }

    @Test func renameNotSureAndVideos() throws {
        let s = session([media("u.jpg"), media("v.mov", .video)], states: [:],
                        dates: ["u.jpg": "2024-05-12", "v.mov": "2024-05-12"])
        let p = try plan(s, opts(rename: true, choice: .notSureFolder))
        let names = Set(p.entries.map { $0.destination.lastPathComponent })
        #expect(names == ["2024-05-12_Not sure_001.jpg", "2024-05-12_Videos_001.mov"])
    }

    @Test func renameWithDateFoldersKeepsCategory() throws {
        let s = session([media("a.jpg")], states: ["a.jpg": .manual(food.id)], dates: ["a.jpg": "2024-05-12"])
        #expect(rel(try plan(s, opts(dateFolders: true, rename: true))) == ["Food/2024-05/2024-05-12_Food_001.jpg"])
    }

    @Test func renameKeepsUnreadableNameAndRollsToFourDigits() throws {
        var files: [MediaFile] = []
        var states: [MediaID: PhotoState] = [:]
        for i in 0..<1001 {
            let n = String(format: "p%04d.jpg", i)
            files.append(media(n)); states[n] = .manual(food.id)
        }
        files.append(media("bad.JPG")); states["bad.JPG"] = .unreadable
        let p = try plan(session(files, states: states), opts(rename: true))
        let names = Set(p.entries.map { $0.destination.lastPathComponent })
        #expect(names.contains("2024-01-01_Food_999.jpg"))
        #expect(names.contains("2024-01-01_Food_1001.jpg"))
        #expect(names.contains("bad.JPG"))
    }

    @Test func collisionAddsSuffix() throws {
        let s = session([media("x/a.jpg"), media("y/a.jpg")],
                        states: ["x/a.jpg": .manual(food.id), "y/a.jpg": .manual(food.id)])
        #expect(rel(try plan(s, opts())) == ["Food/a.jpg", "Food/a 2.jpg"])
        let p2 = try plan(s, opts()) { url in url.lastPathComponent == "Food" ? ["A.jpg"] : [] }
        #expect(rel(p2) == ["Food/a 2.jpg", "Food/a 3.jpg"])
    }

    @Test func notSureChoices() throws {
        let u = media("u.jpg")
        let s = session([u], states: ["u.jpg": .heldNotSure(assignment(pets))])
        let best = try plan(s, opts(choice: .acceptBestGuess))
        #expect(rel(best) == ["Pets/u.jpg"])
        #expect(best.leftInSource == 0)
        let folder = try plan(s, opts(choice: .notSureFolder))
        #expect(rel(folder) == ["Not sure/u.jpg"])
        let leave = try plan(s, opts(choice: .leaveInSource))
        #expect(leave.entries.isEmpty)
        #expect(leave.leftInSource == 1)
        // best category deleted -> Not sure
        let gone = session([u], states: ["u.jpg": .auto(assignment(pets, uncertain: true))], categories: [food])
        #expect(rel(try plan(gone, opts())) == ["Not sure/u.jpg"])
    }

    @Test func dontMoveStays() throws {
        let s = session([media("a.jpg")], states: ["a.jpg": .dontMove])
        let p = try plan(s, opts())
        #expect(p.entries.isEmpty)
        #expect(p.leftInSource == 1)
    }

    @Test func videosAndUnreadable() throws {
        let s = session([media("v.mov", .video), media("bad.jpg"), media("a.jpg")],
                        states: ["bad.jpg": .unreadable, "a.jpg": .manual(pets.id)])
        let p = try plan(s, opts())
        #expect(rel(p) == ["Videos/v.mov", "Unreadable/bad.jpg", "Pets/a.jpg"])
        #expect(p.folderCounts.map(\.folder) == ["Pets", "Videos", "Unreadable"])
        #expect(p.folderCounts.map(\.count) == [1, 1, 1])
    }

    @Test func folderNames() throws {
        #expect(SortPlanner.folderName(for: "A/B:C") == "A-B-C")
        #expect(SortPlanner.folderName(for: ".hidden") == "-hidden")
        #expect(SortPlanner.folderName(for: "   ") == "Untitled")
        let c1 = Category(id: UUID(), displayName: "A/B", emoji: "", prompts: [], exampleIDs: [], order: 0)
        let c2 = Category(id: UUID(), displayName: "A:B", emoji: "", prompts: [], exampleIDs: [], order: 1)
        let s = session([media("1.jpg"), media("2.jpg")], states: ["1.jpg": .manual(c1.id), "2.jpg": .manual(c2.id)],
                        categories: [c1, c2])
        #expect(rel(try plan(s, opts())) == ["A-B/1.jpg", "A-B 2/2.jpg"])
    }

    @Test func refusesSourceAsDestination() throws {
        let t = try TempDir()
        let source = t.url.appending(path: "photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "trip"), withIntermediateDirectories: true)
        let s = session([media("trip/a.jpg"), media("b.jpg")], states: [:])
        let planner = SortPlanner(timeZone: utc)
        func run(_ d: URL) throws -> SortPlan {
            try planner.plan(s, source: source,
                             options: SortOptions(destination: d, mode: .copy, dateFolders: false, rename: false, notSureChoice: .notSureFolder),
                             existingNames: { _ in [] })
        }
        #expect(throws: SortPlanError.destinationIsSource) { try run(source) }
        #expect(throws: SortPlanError.destinationInsideSource) { try run(source.appending(path: "trip/out")) }
        #expect(throws: SortPlanError.destinationInsideSource) { try run(source.appending(path: "trip")) }
        // Final review I2: a folder inside the source with no photos is refused too. The scan cannot skip it.
        #expect(throws: SortPlanError.destinationInsideSource) { try run(source.appending(path: "sorted")) }
        // Case and Unicode form do not matter on APFS.
        #expect(throws: SortPlanError.destinationInsideSource) {
            try run(source.deletingLastPathComponent().appending(path: "PHOTOS/sorted"))
        }
        _ = try run(source.deletingLastPathComponent().appending(path: "photos - sorted"))
    }

    /// Final review M5: the parent of the source as the destination, with a folder that has the name of the source.
    @Test func refusesCategoryFolderInsideSource() throws {
        let parent = URL(filePath: "/tmp/ps-parent", directoryHint: .isDirectory)
        let planner = SortPlanner(timeZone: utc)
        let s = session([media("a.jpg"), media("u.jpg")],
                        states: ["a.jpg": .manual(food.id), "u.jpg": .auto(assignment(pets, uncertain: true))],
                        dates: ["a.jpg": "2024-05-12"])
        func run(_ source: String, dateFolders: Bool = false, choice: NotSureChoice = .acceptBestGuess) throws -> SortPlan {
            try planner.plan(s, source: parent.appending(path: source, directoryHint: .isDirectory),
                             options: SortOptions(destination: parent, mode: .copy, dateFolders: dateFolders,
                                                  rename: false, notSureChoice: choice),
                             existingNames: { _ in [] })
        }
        // The Food category folder is the source.
        #expect(throws: SortPlanError.categoryFolderInsideSource) { try run("Food") }
        #expect(throws: SortPlanError.categoryFolderInsideSource) { try run("food") }
        // The Not sure folder is the source.
        #expect(throws: SortPlanError.categoryFolderInsideSource) { try run("Not sure", choice: .notSureFolder) }
        // The date folder `Food/2024-05` is the source.
        #expect(throws: SortPlanError.categoryFolderInsideSource) { try run("Food/2024-05", dateFolders: true) }
        // Other names are accepted: the folders sit next to the source.
        #expect(try run("Trip").entries.count == 2)
        // A folder with no files is not made, so it does not count.
        #expect(try run("Not sure").entries.count == 2)
    }

    /// Review Focus 5: a trashed photo is in `scan.media` but never in a sort plan or the left count.
    @Test func planSkipsTrashedMedia() throws {
        var s = session([media("a.jpg"), media("b.jpg"), media("c.jpg"), media("v.mov", .video)],
                        states: ["a.jpg": .manual(food.id), "c.jpg": .dontMove])
        s.trashed = [TrashedPhoto(mediaID: "a.jpg", trashPath: "/T/a.jpg", time: Date()),
                     TrashedPhoto(mediaID: "b.jpg", trashPath: "/T/b.jpg", time: Date()),
                     TrashedPhoto(mediaID: "v.mov", trashPath: "/T/v.mov", time: Date())]
        let p = try plan(s, opts(choice: .notSureFolder))
        #expect(p.entries.isEmpty)
        #expect(p.leftInSource == 1)  // c.jpg only.
        #expect(p.folderCounts.isEmpty)
    }
}
