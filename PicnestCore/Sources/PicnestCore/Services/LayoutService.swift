import Foundation

/// The rules for the layout draft. Pure functions on a `LayoutDocument` or a `Session`.
public enum LayoutService {
    /// Adds the ids that are not in the document yet, in the given order. `index` nil appends;
    /// an index past the end appends. Returns false when nothing was added.
    @discardableResult
    public static func add(_ ids: [MediaID], to d: inout LayoutDocument, at index: Int? = nil) -> Bool {
        var seen = Set(d.photoIDs)
        let new = ids.filter { seen.insert($0).inserted }
        guard !new.isEmpty else { return false }
        let at = min(max(index ?? d.photoIDs.count, 0), d.photoIDs.count)
        d.photoIDs.insert(contentsOf: new, at: at)
        return true
    }

    @discardableResult
    public static func remove(_ ids: [MediaID], from d: inout LayoutDocument) -> Bool {
        let drop = Set(ids)
        let before = d.photoIDs.count
        d.photoIDs.removeAll { drop.contains($0) }
        return d.photoIDs.count != before
    }

    /// Moves the photo so it ends at `index` (clamped). Returns false when it is missing or does not move.
    @discardableResult
    public static func move(_ id: MediaID, to index: Int, in d: inout LayoutDocument) -> Bool {
        guard let from = d.photoIDs.firstIndex(of: id) else { return false }
        let to = min(max(index, 0), d.photoIDs.count - 1)
        guard to != from else { return false }
        d.photoIDs.remove(at: from)
        d.photoIDs.insert(id, at: to)
        return true
    }

    @discardableResult
    public static func swap(_ a: MediaID, _ b: MediaID, in d: inout LayoutDocument) -> Bool {
        guard a != b, let i = d.photoIDs.firstIndex(of: a), let j = d.photoIDs.firstIndex(of: b) else { return false }
        d.photoIDs.swapAt(i, j)
        return true
    }

    /// Gives the draft photos their new ids after a rescan or a move. Ids not in `map` stay. No repeats.
    public static func rekey(_ map: [MediaID: String], in s: inout Session) {
        guard var d = s.layoutDraft else { return }
        var seen = Set<MediaID>()
        d.photoIDs = d.photoIDs.map { map[$0] ?? $0 }.filter { seen.insert($0).inserted }
        s.layoutDraft = d
    }

    /// Drops the draft photos that are not in `ids`.
    public static func prune(keeping ids: Set<MediaID>, in s: inout Session) {
        guard s.layoutDraft != nil else { return }
        s.layoutDraft?.photoIDs.removeAll { !ids.contains($0) }
    }
}
