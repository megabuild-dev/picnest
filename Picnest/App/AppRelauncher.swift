import AppKit

/// Relaunches the app after a quit that was confirmed. The Restart button asks for a relaunch, then
/// quits the normal way. The new copy starts only in `relaunchIfRequested`, which runs when the quit
/// goes ahead. A cancelled quit (a sort is running) clears the request.
@MainActor
final class AppRelauncher {
    nonisolated static let openPath = "/usr/bin/open"

    private(set) var isRequested = false
    private let canSpawn: () -> Bool
    private let spawn: () -> Void

    /// The default spawns `open -n <bundle>`.
    init(
        canSpawn: @escaping () -> Bool = { FileManager.default.isExecutableFile(atPath: AppRelauncher.openPath) },
        spawn: @escaping () -> Void = AppRelauncher.openNewCopy
    ) {
        self.canSpawn = canSpawn
        self.spawn = spawn
    }

    /// Asks for a relaunch at the next confirmed quit. Returns false, and sets nothing, when `open` is missing.
    @discardableResult
    func request() -> Bool {
        guard canSpawn() else { return false }
        isRequested = true
        return true
    }

    /// The quit was cancelled: a later normal quit must not relaunch.
    func cancel() { isRequested = false }

    /// Starts the new copy once, if a relaunch was requested.
    func relaunchIfRequested() {
        guard isRequested else { return }
        isRequested = false
        spawn()
    }

    nonisolated private static func openNewCopy() {
        let process = Process()
        process.executableURL = URL(filePath: openPath)
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try? process.run()
    }
}
