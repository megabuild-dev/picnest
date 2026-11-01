import Foundation

/// The rules for favorites and collections. Pure functions on a `Session`.
/// A "usable id" is in `scan.media` and not trashed. The functions ignore other ids.
public enum CollectionService {
    /// Trims spaces, then compares in NFC form and ignoring case. A category can have the same name.
    public static func validateName(
        _ name: String, excluding: CollectionID?, among: [PhotoCollection]
    ) -> CollectionNameIssue? {
        let key = normalized(name)
        if key.isEmpty { return .empty }
        let clash = among.contains { $0.id != excluding && normalized($0.name) == key }
        return clash ? .duplicate : nil
    }

    /// If every usable id is a favorite, removes them all. Otherwise adds them all (the rule of Apple Photos).
    @discardableResult
    public static func toggleFavorite(_ ids: [MediaID], in s: inout Session) -> Bool {
        let usable = usableIDs(ids, in: s)
        guard !usable.isEmpty else { return false }
        if usable.allSatisfy({ s.favoriteIDs.contains($0) }) {
            s.favoriteIDs.subtract(usable)
        } else {
            s.favoriteIDs.formUnion(usable)
        }
        return true
    }

    /// Makes a collection with the trimmed name and the usable ids. Returns nil when the name has an issue.
    public static func create(name: String, adding ids: [MediaID], in s: inout Session) -> CollectionID? {
        guard validateName(name, excluding: nil, among: s.collections) == nil else { return nil }
        let order = (s.collections.map(\.order).max() ?? -1) + 1
        let c = PhotoCollection(
            name: trimmed(name), memberIDs: unique(usableIDs(ids, in: s)), order: order)
        s.collections.append(c)
        return c.id
    }

    @discardableResult
    public static func rename(_ c: CollectionID, to name: String, in s: inout Session) -> Bool {
        guard let i = s.collections.firstIndex(where: { $0.id == c }),
              validateName(name, excluding: c, among: s.collections) == nil else { return false }
        let new = trimmed(name)
        guard s.collections[i].name != new else { return false }
        s.collections[i].name = new
        return true
    }

    /// Deletes the collection and renumbers the `order` of the others from 0.
    @discardableResult
    public static func delete(_ c: CollectionID, in s: inout Session) -> Bool {
        guard s.collections.contains(where: { $0.id == c }) else { return false }
        s.collections.removeAll { $0.id == c }
        let sorted = s.collections.sorted { $0.order < $1.order }
        s.collections = sorted.enumerated().map { i, col in
            var col = col
            col.order = i
            return col
        }
        return true
    }

    /// Appends the usable ids in the given order. Ids already in the collection are not added again.
    @discardableResult
    public static func add(_ ids: [MediaID], to c: CollectionID, in s: inout Session) -> Bool {
        guard let i = s.collections.firstIndex(where: { $0.id == c }) else { return false }
        let present = Set(s.collections[i].memberIDs)
        let new = unique(usableIDs(ids, in: s)).filter { !present.contains($0) }
        guard !new.isEmpty else { return false }
        s.collections[i].memberIDs.append(contentsOf: new)
        return true
    }

    @discardableResult
    public static func remove(_ ids: [MediaID], from c: CollectionID, in s: inout Session) -> Bool {
        guard let i = s.collections.firstIndex(where: { $0.id == c }) else { return false }
        let drop = Set(ids)
        let before = s.collections[i].memberIDs.count
        s.collections[i].memberIDs.removeAll { drop.contains($0) }
        return s.collections[i].memberIDs.count != before
    }

    /// Moves favorites and members to their new ids after a rescan or a move. Ids not in `map` stay.
    public static func rekey(_ map: [MediaID: String], in s: inout Session) {
        s.favoriteIDs = Set(s.favoriteIDs.map { map[$0] ?? $0 })
        for i in s.collections.indices {
            s.collections[i].memberIDs = unique(s.collections[i].memberIDs.map { map[$0] ?? $0 })
        }
    }

    /// Drops favorites and members that are not in `ids`.
    public static func prune(keeping ids: Set<MediaID>, in s: inout Session) {
        s.favoriteIDs.formIntersection(ids)
        for i in s.collections.indices {
            s.collections[i].memberIDs.removeAll { !ids.contains($0) }
        }
    }

    /// The favorites that are not trashed.
    public static func visibleFavorites(in s: Session) -> Set<MediaID> {
        s.favoriteIDs.subtracting(s.trashedIDs)
    }

    /// The members of the collection that are not trashed, in the order the user added them.
    public static func visibleMembers(of c: CollectionID, in s: Session) -> [MediaID] {
        guard let col = s.collections.first(where: { $0.id == c }) else { return [] }
        let trashed = s.trashedIDs
        return col.memberIDs.filter { !trashed.contains($0) }
    }

    // MARK: - Helpers

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ name: String) -> String {
        trimmed(name).precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func usableIDs(_ ids: [MediaID], in s: Session) -> [MediaID] {
        let known = Set(s.scan.media.map(\.id))
        let trashed = s.trashedIDs
        return ids.filter { known.contains($0) && !trashed.contains($0) }
    }

    private static func unique(_ ids: [MediaID]) -> [MediaID] {
        var seen = Set<MediaID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
