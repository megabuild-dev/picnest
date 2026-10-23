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
}
