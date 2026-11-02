import Foundation
@testable import PicnestCore

/// A `FileOps` that fails `move` after the temp file exists.
struct FailingMoveOps: FileOps {
    struct MoveFailed: Error {}
    let base = LocalFileOps()
    func exists(_ u: URL) -> Bool { base.exists(u) }
    func makeFolder(_ u: URL) throws { try base.makeFolder(u) }
    func copy(_ from: URL, _ to: URL) throws { try base.copy(from, to) }
    func size(_ u: URL) throws -> Int64 { try base.size(u) }
    func modified(_ u: URL) throws -> Date { try base.modified(u) }
    func remove(_ u: URL) throws { try base.remove(u) }
    func removeEmptyFolder(_ u: URL) throws { try base.removeEmptyFolder(u) }
    func isEmptyFolder(_ u: URL) -> Bool { base.isEmptyFolder(u) }
    func names(in folder: URL) -> Set<String> { base.names(in: folder) }
    func trash(_ u: URL) throws -> URL? { try base.trash(u) }
    func move(_ from: URL, _ to: URL) throws { throw MoveFailed() }
}
