import Foundation

extension MediaFile {
    /// The key of the on-disk caches (spec 4.2): relative path, size, and modification time in ms.
    /// A changed file gets a new key, so a cache never returns a stale value for it.
    var cacheKey: String {
        "\(relativePath)|\(size)|\(Int64(modified.timeIntervalSince1970 * 1000))"
    }
}
