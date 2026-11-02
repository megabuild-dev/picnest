import AppKit
import Testing
@testable import Picnest

/// Final review M4: the app does not quit while a sort or an undo changes files.
@MainActor
struct AppDelegateTests {
    @Test func quitIsCancelledWhileASortRuns() {
        #expect(AppDelegate.terminateReply(sortIsRunning: true) == .terminateCancel)
        #expect(AppDelegate.terminateReply(sortIsRunning: false) == .terminateNow)
        #expect(AppDelegate.sortRunningMessage == "A sort is running. Stop it first, then quit.")
    }

    // MARK: - Quit while an editor exports (final review I1)

    private func delegate(
        sort: Bool = false, export: Bool = false, edits: Bool = false, confirm: Bool = true,
        relauncher: AppRelauncher = AppRelauncher(canSpawn: { true }, spawn: {})
    ) -> (delegate: AppDelegate, alerts: Alerts) {
        let alerts = Alerts()
        let delegate = AppDelegate(
            environment: nil, relauncher: relauncher, sortRunningCheck: { sort },
            exportRunningCheck: { export }, unexportedEditsCheck: { edits })
        delegate.showSortRunningAlert = { alerts.sort += 1 }
        delegate.showExportRunningAlert = { alerts.export += 1 }
        delegate.confirmQuitWithEdits = { alerts.asked += 1; return confirm }
        delegate.flushEditors = { alerts.flushed += 1 }
        return (delegate, alerts)
    }

    @MainActor final class Alerts { var sort = 0, export = 0, asked = 0, flushed = 0 }

    @Test func quitIsCancelledWhileAnExportRuns() {
        let (delegate, alerts) = delegate(export: true)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(alerts.export == 1 && alerts.asked == 0 && alerts.flushed == 0)
        #expect(AppDelegate.exportRunningMessage == "An export is running. Wait for it to finish, then quit.")
    }

    @Test func restartIsCancelledWhileAnExportRuns() {
        let relauncher = AppRelauncher(canSpawn: { true }, spawn: {})
        let (delegate, _) = delegate(export: true, relauncher: relauncher)
        #expect(relauncher.request())
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(!relauncher.isRequested)
    }

    @Test func quitWithUnexportedEditsAsksFirst() {
        let (declined, alerts) = delegate(edits: true, confirm: false)
        #expect(declined.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(alerts.asked == 1 && alerts.flushed == 0)
        let (accepted, other) = delegate(edits: true, confirm: true)
        #expect(accepted.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(other.asked == 1 && other.flushed == 1)
    }

    @Test func aSortStillWinsOverAnExport() {
        let (delegate, alerts) = delegate(sort: true, export: true)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(alerts.sort == 1 && alerts.export == 0)
    }

    @Test func quitWithNothingOpenSavesTheLayoutDraftAndGoes() {
        let (delegate, alerts) = delegate()
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(alerts.flushed == 1 && alerts.asked == 0)
    }

    // MARK: - Window close (re-review I-A)

    @Test func closingTheWindowRunsTheQuitChecks() {
        let (busy, alerts) = delegate(export: true)
        #expect(!busy.confirmLeaving())
        #expect(alerts.export == 1 && alerts.flushed == 0)
        let (declined, other) = delegate(edits: true, confirm: false)
        #expect(!declined.confirmLeaving() && other.asked == 1 && other.flushed == 0)
        let (idle, third) = delegate()
        #expect(idle.confirmLeaving() && third.flushed == 1)
    }

    @MainActor final class OriginalDelegate: NSObject, NSWindowDelegate {
        var asked = 0
        var answer = true
        func windowShouldClose(_ sender: NSWindow) -> Bool { asked += 1; return answer }
    }

    @Test func windowDelegateAsksTheGuardThenTheOriginal() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let original = OriginalDelegate()
        window.delegate = original
        var allowed = false
        let guardDelegate = WindowCloseDelegate(allow: { allowed })
        guardDelegate.install(on: window)
        #expect(window.delegate === guardDelegate)
        #expect(!guardDelegate.windowShouldClose(window) && original.asked == 0)
        allowed = true
        #expect(guardDelegate.windowShouldClose(window) && original.asked == 1)
        original.answer = false
        #expect(!guardDelegate.windowShouldClose(window))
        #expect(guardDelegate.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))))
        guardDelegate.install(on: window)  // twice: still wraps the original only
        #expect(guardDelegate.original === original)
    }

    @Test func delegateAsksTheLibrary() throws {
        let temp = try TempDir()
        let suite = TestDefaults()
        let environment = AppEnvironment(
            embedder: FakeEmbedder(), sessionsRoot: temp.url.appending(path: "Sessions"), defaults: suite.defaults)
        let delegate = AppDelegate(environment: environment)
        #expect(delegate.isSortRunning() == false)
        #expect(delegate.environment === environment)
        #expect(delegate.app != nil)
    }

    /// Spec 8: the updater must not start in the test host, which must not read the network or the Keychain.
    /// `quitIsCancelledWhileASortRuns` covers the other half: the quit guard also stops an install at quit.
    @Test func theTestHostStartsNoUpdater() {
        let delegate = AppDelegate()
        #expect(delegate.environment == nil)
        #expect(delegate.updater == nil)
    }

    @Test func delegateMakesTheUpdaterOnce() {
        let fake = FakeUpdater()
        var made = 0
        let delegate = AppDelegate(environment: nil, makeUpdater: {
            made += 1
            return fake
        })
        #expect(made == 1)
        #expect(delegate.updater === fake)
    }

    @Test func menuItemFollowsCanCheckForUpdates() {
        let fake = FakeUpdater(canCheckForUpdates: true)
        let model = UpdaterViewModel(updater: fake)
        #expect(model.canCheckForUpdates)
        fake.setCanCheck(false)
        #expect(model.canCheckForUpdates == false)
        fake.setCanCheck(true)
        #expect(model.canCheckForUpdates)
    }

    @Test func menuItemStartsACheck() {
        let fake = FakeUpdater()
        let model = UpdaterViewModel(updater: fake)
        model.checkForUpdates()
        #expect(fake.checkCount == 1)
    }

    @Test func viewModelReleasesTheSubscription() {
        let fake = FakeUpdater()
        var model: UpdaterViewModel? = UpdaterViewModel(updater: fake)
        #expect(fake.hasObserver)
        model = nil
        #expect(fake.hasObserver == false)
        _ = model
    }
}

/// An updater that uses no network and no Keychain.
@MainActor
final class FakeUpdater: AppUpdater {
    private(set) var canCheckForUpdates: Bool
    private(set) var checkCount = 0
    private var handler: (@MainActor (Bool) -> Void)?
    private weak var token: Token?

    var hasObserver: Bool { token != nil }

    init(canCheckForUpdates: Bool = true) {
        self.canCheckForUpdates = canCheckForUpdates
    }

    func checkForUpdates() { checkCount += 1 }

    func observeCanCheckForUpdates(_ onChange: @escaping @MainActor (Bool) -> Void) -> AnyObject {
        handler = onChange
        let token = Token()
        self.token = token
        return token
    }

    func setCanCheck(_ value: Bool) {
        canCheckForUpdates = value
        handler?(value)
    }

    final class Token {}
}
