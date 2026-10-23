import Foundation

/// The file operations that a sort and an undo use. Tests wrap `LocalFileOps` to inject failures.
public protocol FileOps: Sendable {
    func exists(_ u: URL) -> Bool
    /// Makes 1 folder. The parent must exist.
    func makeFolder(_ u: URL) throws
    /// Copies a file with its metadata. Fails if `to` exists.
    func copy(_ from: URL, _ to: URL) throws
    func size(_ u: URL) throws -> Int64
    func modified(_ u: URL) throws -> Date
    /// Removes 1 file. Never call it on a folder (a folder remove is recursive).
    func remove(_ u: URL) throws
    /// Removes a folder only if it is empty (a lone `.DS_Store` file is removed first).
    /// Does nothing if the folder holds other files or does not exist. Never recursive.
    func removeEmptyFolder(_ u: URL) throws
    /// True if the folder exists and holds nothing (a Finder `.DS_Store` file does not count).
    func isEmptyFolder(_ u: URL) -> Bool
    /// The file names in a folder. Empty if the folder does not exist.
    func names(in folder: URL) -> Set<String>
    /// Moves 1 file to the user's Trash and returns its URL in the Trash (spec 7.4). Never deletes it:
    /// on a volume with no Trash this throws and the file stays. Returns nil when the file is in the
    /// Trash but the system did not tell where.
    func trash(_ u: URL) throws -> URL?
    /// Moves 1 file. Throws, and changes nothing, if a file exists at `to`. Never overwrites.
    func move(_ from: URL, _ to: URL) throws
}

public struct LocalFileOps: FileOps {
    static let ignoredNames: Set<String> = [".DS_Store"]

    public init() {}

    public func exists(_ u: URL) -> Bool {
        FileManager.default.fileExists(atPath: u.path)
    }

    public func makeFolder(_ u: URL) throws {
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
    }

    public func copy(_ from: URL, _ to: URL) throws {
        try FileManager.default.copyItem(at: from, to: to)
    }

    public func size(_ u: URL) throws -> Int64 {
        Int64(try Self.fresh(u).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }

    public func modified(_ u: URL) throws -> Date {
        guard let d = try Self.fresh(u).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: u])
        }
        return d
    }

    public func remove(_ u: URL) throws {
        try FileManager.default.removeItem(at: u)
    }

    public func removeEmptyFolder(_ u: URL) throws {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? []
        if names.count == 1, let only = names.first, Self.ignoredNames.contains(only) {
            try? FileManager.default.removeItem(at: u.appending(path: only, directoryHint: .notDirectory))
        }
        // rmdir(2) removes only an empty folder. A file added at any time before this call keeps it.
        guard rmdir(u.path) != 0 else { return }
        let code = errno
        if code == ENOTEMPTY || code == EEXIST || code == ENOENT { return }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO, userInfo: [NSURLErrorKey: u])
    }

    public func isEmptyFolder(_ u: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue,
              let names = try? FileManager.default.contentsOfDirectory(atPath: u.path) else { return false }
        return names.allSatisfy { Self.ignoredNames.contains($0) }
    }

    public func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    public func trash(_ u: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: u, resultingItemURL: &result)
        return result as URL?
    }

    public func move(_ from: URL, _ to: URL) throws {
        // RENAME_EXCL makes the check and the rename 1 step: an existing `to` is never replaced.
        if renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 { return }
        let code = errno
        guard code == EXDEV else {
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO, userInfo: [NSURLErrorKey: to])
        }
        // Another volume: FileManager copies, then removes the source. It stops if `to` exists.
        guard !exists(to) else { throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: to]) }
        try FileManager.default.moveItem(at: from, to: to)
    }

    /// A copy of the URL with no cached resource values, so a file changed since the last read is seen.
    private static func fresh(_ u: URL) -> URL {
        var copy = u
        copy.removeAllCachedResourceValues()
        return copy
    }
}
