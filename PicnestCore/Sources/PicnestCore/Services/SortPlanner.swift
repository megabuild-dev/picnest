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

    /// The folder name of each category: its stored `folderName`, or else its safe display name, with " 2",
    /// " 3"... added to a name that another category or a reserved folder already uses (spec 7.2).
    public static func folderNames(for categories: [Category]) -> [CategoryID: String] {
        let ordered = categories.sorted { $0.order < $1.order }
        var used = reservedKeys
        var folderOf: [CategoryID: String] = [:]
        for c in ordered {
            guard let stored = c.folderName else { continue }
            folderOf[c.id] = stored
            used.insert(key(stored))
        }
        for c in ordered where c.folderName == nil {
            let name = unique(folderName(for: c.displayName), avoiding: used)
            used.insert(key(name))
            folderOf[c.id] = name
        }
        return folderOf
    }

    /// A folder name for `displayName` that no other category and no reserved folder uses. `excluding` is
    /// the category that is renamed: its own folder name does not count.
    public static func uniqueFolderName(
        for displayName: String, among categories: [Category], excluding: CategoryID? = nil
    ) -> String {
        let others = folderNames(for: categories).filter { $0.key != excluding }
        return unique(folderName(for: displayName), avoiding: reservedKeys.union(others.values.map(key)))
    }

    private static var reservedKeys: Set<String> {
        [key(notSureFolder), key(videosFolder), key(unreadableFolder)]
    }

    private static func unique(_ base: String, avoiding used: Set<String>) -> String {
        var candidate = base
        var n = 2
        while used.contains(key(candidate)) { candidate = "\(base) \(n)"; n += 1 }
        return candidate
    }

    /// The folder part of a relative path, or "" for a file at the source root.
    private static func parentFolder(of relativePath: String) -> String {
        (relativePath as NSString).deletingLastPathComponent
    }

    public func plan(_ s: Session, source: URL, options: SortOptions, existingNames: (URL) -> Set<String>) throws -> SortPlan {
        try checkDestination(source: source, destination: options.destination)
        return try build(
            s, source: source, destination: options.destination, rename: options.rename,
            dateFolders: options.dateFolders, notSureChoice: options.notSureChoice, inPlace: false,
            existingNames: existingNames)
    }

    /// The in-place plan: every visible photo moves into `<source>/<category folder>` and is renamed to
    /// date + category + number (spec 7.2). The folders live inside the source on purpose, so the
    /// destination guards do not run. A photo that already sits directly in its target folder keeps its
    /// place and name, so a second organize only handles photos that are still loose.
    public func planInPlace(
        _ s: Session, source: URL, rename: Bool = true, existingNames: (URL) -> Set<String>
    ) throws -> SortPlan {
        try build(
            s, source: source, destination: source, rename: rename, dateFolders: false,
            notSureChoice: .notSureFolder, inPlace: true, existingNames: existingNames)
    }

    private func build(
        _ s: Session, source: URL, destination: URL, rename: Bool, dateFolders: Bool,
        notSureChoice: NotSureChoice, inPlace: Bool, existingNames: (URL) -> Set<String>
    ) throws -> SortPlan {
        let ordered = s.categories.sorted { $0.order < $1.order }
        let folderOf = Self.folderNames(for: s.categories)

        // Decide the top-level folder of each media file. nil means it stays in the source.
        struct Item { var media: MediaFile; var folder: String; var date: Date }
        var items: [Item] = []
        var left = 0
        for m in s.visibleMedia {  // A trashed photo is in no sort (spec 7.4).
            guard let folder = topFolder(for: m, state: s.states[m.id], folderOf: folderOf, choice: notSureChoice) else {
                left += 1
                continue
            }
            // In place: a photo that is already in its target folder keeps its place and name.
            if inPlace, Self.parentFolder(of: m.relativePath) == folder { continue }
            items.append(Item(media: m, folder: folder, date: s.scan.dates[m.id]?.date ?? m.modified))
        }

        let dayFormatter = Self.formatter("yyyy-MM-dd", timeZone)
        let monthFormatter = Self.formatter("yyyy-MM", timeZone)

        // Group by destination folder (including the date subfolder).
        var groups: [String: [Item]] = [:]
        var groupURL: [String: URL] = [:]
        var groupOrder: [String] = []
        for item in items {
            var url = destination.appending(path: item.folder, directoryHint: .isDirectory)
            if dateFolders {
                url = url.appending(path: monthFormatter.string(from: item.date), directoryHint: .isDirectory)
            }
            let k = url.path
            if groups[k] == nil { groupURL[k] = url; groupOrder.append(k) }
            groups[k, default: []].append(item)
        }

        if !inPlace { try checkFolders(groupOrder.compactMap { groupURL[$0] }, source: source) }

        var destOf: [MediaID: URL] = [:]
        for k in groupOrder {
            guard let folderURL = groupURL[k], var group = groups[k] else { continue }
            if rename {
                group.sort { ($0.date, $0.media.relativePath) < ($1.date, $1.media.relativePath) }
            } else {
                group.sort { $0.media.relativePath < $1.media.relativePath }
            }
            var taken = Set(existingNames(folderURL).map(Self.key))
            var counters: [String: Int] = [:]
            for item in group {
                let original = (item.media.relativePath as NSString).lastPathComponent
                var name = original
                if rename, item.folder != Self.unreadableFolder {
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
