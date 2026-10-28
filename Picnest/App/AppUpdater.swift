import Foundation
import Sparkle

/// What the app needs from an updater (spec 8). The tests replace it with a fake, so they use no network
/// and no Keychain.
@MainActor
protocol AppUpdater: AnyObject {
    var canCheckForUpdates: Bool { get }

    /// Starts a check that the user asked for. The updater shows its own window.
    func checkForUpdates()

    /// Calls `onChange` on the main actor each time `canCheckForUpdates` changes. The subscription lasts
    /// as long as the returned token.
    func observeCanCheckForUpdates(_ onChange: @escaping @MainActor (Bool) -> Void) -> AnyObject
}

/// The Sparkle updater. It starts at once: it checks the appcast on a schedule and installs a new version
/// at quit.
@MainActor
final class SparkleAppUpdater: AppUpdater {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    func observeCanCheckForUpdates(_ onChange: @escaping @MainActor (Bool) -> Void) -> AnyObject {
        controller.updater.observe(\.canCheckForUpdates, options: [.new]) { _, change in
            // The change carries the new value, so no code reads the main-actor property off the main actor.
            let canCheck = change.newValue ?? false
            Task { @MainActor in onChange(canCheck) }
        }
    }
}
