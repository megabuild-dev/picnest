import AppKit

/// Owns the 1 app environment, the 1 `AppModel`, and the 1 Sparkle updater, and stops a quit while a
/// sort or an undo changes files (final review M4). A quit in the middle of a copy leaves a part file
/// that the journal does not know.
///
/// Sparkle installs a new version at quit, so the same guard already stops an install while a sort runs:
/// the app refuses to quit, and Sparkle keeps the update for the next quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let sortRunningMessage = String(localized: "A sort is running. Stop it first, then quit.")

    /// Nil in the test host: tests make their own environment.
    let environment: AppEnvironment?
    let app: AppModel?

    /// The updater behind Picnest > Check for Updates… (spec 8). Nil in the test host, which must not read
    /// the network or the login Keychain.
    let updater: (any AppUpdater)?

    /// Relaunches the app at a confirmed quit, for the Restart button in Settings.
    let relauncher: AppRelauncher

    /// Replaces the library check. Tests use it to fake a running sort.
    private let sortRunningCheck: (() -> Bool)?

    /// Shows the "sort is running" alert. Tests replace it.
    var showSortRunningAlert: () -> Void = {
        let alert = NSAlert()
        alert.messageText = AppDelegate.sortRunningMessage
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// The app: the bundled model, Application Support, standard defaults, and the updater.
    /// The test host must not read the real Application Support or standard defaults, or use the
    /// network, so it gets neither.
    override convenience init() {
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.init(
            environment: isTestHost ? nil : AppEnvironment(),
            makeUpdater: isTestHost ? nil : { SparkleAppUpdater() })
    }

    init(
        environment: AppEnvironment?, makeUpdater: (() -> any AppUpdater)? = nil,
        relauncher: AppRelauncher = AppRelauncher(), sortRunningCheck: (() -> Bool)? = nil
    ) {
        self.sortRunningCheck = sortRunningCheck
        self.environment = environment
        self.relauncher = relauncher
        app = environment.map { AppModel(environment: $0) }
        // Checks the appcast on a schedule and installs a new version at quit.
        updater = makeUpdater?()
        super.init()
    }

    /// True while a sort or an undo changes files.
    func isSortRunning() -> Bool {
        sortRunningCheck?() ?? environment?.library.isSortRunning ?? false
    }

    /// The answer to a quit: cancel while a sort or an undo runs.
    static func terminateReply(sortIsRunning: Bool) -> NSApplication.TerminateReply {
        sortIsRunning ? .terminateCancel : .terminateNow
    }

    /// Applies the saved appearance. The test host has no environment, so it changes nothing.
    func applicationDidFinishLaunching(_ notification: Notification) {
        environment?.appearance.applyCurrent()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reply = Self.terminateReply(sortIsRunning: isSortRunning())
        if reply == .terminateCancel {
            relauncher.cancel()
            showSortRunningAlert()
        }
        return reply
    }

    /// Runs only when the quit goes ahead.
    func applicationWillTerminate(_ notification: Notification) {
        relauncher.relaunchIfRequested()
    }
}
