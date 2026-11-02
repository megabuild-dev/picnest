import CryptoKit
import Foundation

/// SHA-256, size, and modification date of a file, to prove that a test did not change it.
struct FileFingerprint: Equatable {
    let sha256: String
    let size: Int
    let modified: Date

    init(of url: URL) throws {
        let data = try Data(contentsOf: url)
        sha256 = Self.sha256(data)
        size = data.count
        var fresh = url
        fresh.removeAllCachedResourceValues()
        modified = try fresh.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Relative path → size and SHA-256 for files; folders end with "/". Empty if the folder does not exist.
    static func snapshot(_ folder: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [:] }
        var out: [String: String] = [:]
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [:] }
        for case let url as URL in e {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            let rel = String(path.dropFirst(root.count + 1))
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                out[rel + "/"] = "dir"
            } else {
                let data = try Data(contentsOf: url)
                out[rel] = "\(data.count) \(sha256(data))"
            }
        }
        return out
    }
}
