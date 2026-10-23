import Foundation

public struct SortPlan: Sendable {
    public var entries: [PlanEntry]
    public var folderCounts: [(folder: String, count: Int)]
    public var leftInSource: Int

    public init(entries: [PlanEntry], folderCounts: [(folder: String, count: Int)], leftInSource: Int) {
        self.entries = entries
        self.folderCounts = folderCounts
        self.leftInSource = leftInSource
    }
}

public enum SortPlanError: Error, Equatable {
    /// The destination is the source folder.
    case destinationIsSource
    /// The destination is inside the source folder. The scan cannot skip it, so a rescan would read the
    /// sorted files as new photos (final review I2).
    case destinationInsideSource
    /// A folder that gets files (a category, Not sure, Videos, Unreadable, or a date sub-folder) is the
    /// source folder or inside it, for example a category with the name of the source folder when the
    /// destination is the parent of the source (final review M5).
    case categoryFolderInsideSource
}

/// Builds the list of file moves for a sort. Pure: `existingNames` is the only window to the disk.
public struct SortPlanner: Sendable {
    static let notSureFolder = "Not sure"
    static let videosFolder = "Videos"
    static let unreadableFolder = "Unreadable"

    private let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// Makes a display name safe to use as a folder name.
    public static func folderName(for displayName: String) -> String {
        var name = displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix(".") { name = "-" + name.dropFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled" : name
    }

    public func plan(_ s: Session, source: URL, options: SortOptions, existingNames: (URL) -> Set<String>) throws -> SortPlan {
        try checkDestination(source: source, destination: options.destination)

        let ordered = s.categories.sorted { $0.order < $1.order }
        var used: Set<String> = [Self.key(Self.notSureFolder), Self.key(Self.videosFolder), Self.key(Self.unreadableFolder)]
        var folderOf: [CategoryID: String] = [:]
        for c in ordered {
            let base = Self.folderName(for: c.displayName)
            var candidate = base
            var n = 2
            while used.contains(Self.key(candidate)) { candidate = "\(base) \(n)"; n += 1 }
            used.insert(Self.key(candidate))
            folderOf[c.id] = candidate
        }

        // Decide the top-level folder of each media file. nil means it stays in the source.
        struct Item { var media: MediaFile; var folder: String; var date: Date }
        var items: [Item] = []
        var left = 0
        for m in s.visibleMedia {  // A trashed photo is in no sort (spec 7.4).
            guard let folder = topFolder(for: m, state: s.states[m.id], folderOf: folderOf, choice: options.notSureChoice) else {
                left += 1
                continue
            }
            items.append(Item(media: m, folder: folder, date: s.scan.dates[m.id]?.date ?? m.modified))
        }

        let dayFormatter = Self.formatter("yyyy-MM-dd", timeZone)
        let monthFormatter = Self.formatter("yyyy-MM", timeZone)

        // Group by destination folder (including the date subfolder).
        var groups: [String: [Item]] = [:]
        var groupURL: [String: URL] = [:]
        var groupOrder: [String] = []
        for item in items {
            var url = options.destination.appending(path: item.folder, directoryHint: .isDirectory)
            if options.dateFolders {
                url = url.appending(path: monthFormatter.string(from: item.date), directoryHint: .isDirectory)
            }
            let k = url.path
            if groups[k] == nil { groupURL[k] = url; groupOrder.append(k) }
            groups[k, default: []].append(item)
        }

        try checkFolders(groupOrder.compactMap { groupURL[$0] }, source: source)

        var destOf: [MediaID: URL] = [:]
        for k in groupOrder {
            guard let folderURL = groupURL[k], var group = groups[k] else { continue }
            if options.rename {
                group.sort { ($0.date, $0.media.relativePath) < ($1.date, $1.media.relativePath) }
            } else {
                group.sort { $0.media.relativePath < $1.media.relativePath }
            }
            var taken = Set(existingNames(folderURL).map(Self.key))
            var counters: [String: Int] = [:]
            for item in group {
                let original = (item.media.relativePath as NSString).lastPathComponent
                var name = original
                if options.rename, item.folder != Self.unreadableFolder {
                    let day = dayFormatter.string(from: item.date)
                    let n = counters[day, default: 0] + 1
                    counters[day] = n
                    let number = n < 1000 ? String(format: "%03d", n) : String(n)
                    var ext = (original as NSString).pathExtension.lowercased()
                    if ext == "jpeg" { ext = "jpg" }
                    name = "\(day)_\(item.folder)_\(number)" + (ext.isEmpty ? "" : ".\(ext)")
                }
                let unique = Self.uniqueName(name, taken: taken)
                taken.insert(Self.key(unique))
                destOf[item.media.id] = folderURL.appending(path: unique, directoryHint: .notDirectory)
            }
        }

        var entries: [PlanEntry] = []
        var counts: [String: Int] = [:]
        for item in items {
            guard let dest = destOf[item.media.id] else { continue }
            entries.append(PlanEntry(
                mediaID: item.media.id,
                source: source.appending(path: item.media.relativePath, directoryHint: .notDirectory),
                destination: dest, size: item.media.size, modified: item.media.modified))
            counts[item.folder, default: 0] += 1
        }

        let folderOrder = ordered.compactMap { folderOf[$0.id] } + [Self.notSureFolder, Self.videosFolder, Self.unreadableFolder]
        let folderCounts = folderOrder.compactMap { f in counts[f].map { (folder: f, count: $0) } }
        return SortPlan(entries: entries, folderCounts: folderCounts, leftInSource: left)
    }

    // MARK: - Helpers

    private func topFolder(for m: MediaFile, state: PhotoState?, folderOf: [CategoryID: String], choice: NotSureChoice) -> String? {
        if case .dontMove? = state { return nil }
        if m.kind == .video { return Self.videosFolder }
        guard let state else { return notSure(best: nil, folderOf: folderOf, choice: choice) }
        switch state {
        case .dontMove: return nil
        case .unreadable: return Self.unreadableFolder
        case .manual(let c): return folderOf[c] ?? Self.notSureFolder
        case .auto(let a) where !a.uncertain: return folderOf[a.categoryID] ?? Self.notSureFolder
        case .auto(let a), .heldNotSure(let a): return notSure(best: a.categoryID, folderOf: folderOf, choice: choice)
        }
    }

    private func notSure(best: CategoryID?, folderOf: [CategoryID: String], choice: NotSureChoice) -> String? {
        switch choice {
        case .leaveInSource: nil
        case .notSureFolder: Self.notSureFolder
        case .acceptBestGuess: best.flatMap { folderOf[$0] } ?? Self.notSureFolder
        }
    }

    private static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func uniqueName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(key(name)) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !taken.contains(key(candidate)) { return candidate }
            n += 1
        }
    }

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    /// Refuses the source folder and any folder inside it as the destination (final review I2).
    private func checkDestination(source: URL, destination: URL) throws {
        let src = Self.key(source.canonicalKeyPath), dst = Self.key(destination.canonicalKeyPath)
        if dst == src { throw SortPlanError.destinationIsSource }
        if Self.isInside(dst, src) { throw SortPlanError.destinationInsideSource }
    }

    /// Refuses a plan that puts files into the source folder or a folder inside it (final review M5).
    private func checkFolders(_ folders: [URL], source: URL) throws {
        let src = Self.key(source.canonicalKeyPath)
        for folder in folders {
            let path = Self.key(folder.canonicalKeyPath)
            if path == src || Self.isInside(path, src) { throw SortPlanError.categoryFolderInsideSource }
        }
    }

    /// True if `path` is inside `folder`. Both are keys (`key(_:)` of a canonical path).
    private static func isInside(_ path: String, _ folder: String) -> Bool {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix)
    }
}
