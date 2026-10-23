import Foundation

extension URL {
    /// Path with symlinks resolved, standardized, and NFC-normalized. Used as a stable key for a folder.
    var canonicalKeyPath: String {
        resolvingSymlinksInPath().standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }
}
