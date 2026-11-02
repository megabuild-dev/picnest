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
    static let exportRunningMessage = String(localized: "An export is running. Wait for it to finish, then quit.")
    static let unexportedEditsMessage = String(localized: "Your edits to a photo are not exported yet.")
    static let unexportedEditsDetail = String(localized: "If you quit now, the edits are lost. The photo itself does not change.")

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

    /// Replace the editor checks. Tests use them to fake a running export and unexported edits.
    private let exportRunningCheck: (() -> Bool)?
    private let unexportedEditsCheck: (() -> Bool)?

    /// Shows the "sort is running" alert. Tests replace it.
    var showSortRunningAlert: () -> Void = {
        let alert = NSAlert()
        alert.messageText = AppDelegate.sortRunningMessage
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// Shows the "export is running" alert. Tests replace it.
    var showExportRunningAlert: () -> Void = {
        let alert = NSAlert()
        alert.messageText = AppDelegate.exportRunningMessage
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// Asks whether to quit and lose the unexported edits of a photo. Returns true for **Quit**.
    var confirmQuitWithEdits: () -> Bool = {
        let alert = NSAlert()
        alert.messageText = AppDelegate.unexportedEditsMessage
        alert.informativeText = AppDelegate.unexportedEditsDetail
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Saves the layout draft of an open editor. Tests replace it.
    lazy var flushEditors: () -> Void = { [weak self] in self?.app?.flushEditors() }

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
        relauncher: AppRelauncher = AppRelauncher(), sortRunningCheck: (() -> Bool)? = nil,
        exportRunningCheck: (() -> Bool)? = nil, unexportedEditsCheck: (() -> Bool)? = nil
    ) {
        self.sortRunningCheck = sortRunningCheck
        self.exportRunningCheck = exportRunningCheck
        self.unexportedEditsCheck = unexportedEditsCheck
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

    /// True while an editor writes an export or has its save panel open.
    func isExportRunning() -> Bool { exportRunningCheck?() ?? app?.isEditorExporting ?? false }

    /// True if a photo editor holds an edit that no export wrote.
    func hasUnexportedEdits() -> Bool { unexportedEditsCheck?() ?? app?.hasUnexportedEdits ?? false }

    /// The answer to a quit: cancel while a sort or an undo runs.
    static func terminateReply(sortIsRunning: Bool) -> NSApplication.TerminateReply {
        sortIsRunning ? .terminateCancel : .terminateNow
    }

    /// Applies the saved appearance. The test host has no environment, so it changes nothing.
    func applicationDidFinishLaunching(_ notification: Notification) {
        environment?.appearance.applyCurrent()
    }

    /// A quit (also the Restart button) and the close of the window stop while a sort or an export runs, because
    /// leaving in the middle of a write leaves a temp file or part of a multi-page export (final review I1).
    /// Unexported photo edits need a yes. The layout draft saves at once. 1 place for both ways out.
    func confirmLeaving() -> Bool {
        if Self.terminateReply(sortIsRunning: isSortRunning()) == .terminateCancel {
            relauncher.cancel()
            showSortRunningAlert()
            return false
        }
        if isExportRunning() {
            relauncher.cancel()
            showExportRunningAlert()
            return false
        }
        if hasUnexportedEdits(), !confirmQuitWithEdits() {
            relauncher.cancel()
            return false
        }
        flushEditors()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmLeaving() ? .terminateNow : .terminateCancel
    }

    /// Runs only when the quit goes ahead.
    func applicationWillTerminate(_ notification: Notification) {
        relauncher.relaunchIfRequested()
    }
}
