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
