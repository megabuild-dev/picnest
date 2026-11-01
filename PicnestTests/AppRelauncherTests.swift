import AppKit
import Foundation
import Testing
@testable import Picnest

/// The Restart button relaunches only after a confirmed quit.
@MainActor
struct AppRelauncherTests {
    private func make(canSpawn: Bool = true) -> (AppDelegate, AppRelauncher, () -> Int) {
        var spawned = 0
        let relauncher = AppRelauncher(canSpawn: { canSpawn }, spawn: { spawned += 1 })
        let delegate = AppDelegate(environment: nil, relauncher: relauncher)
        delegate.showSortRunningAlert = {}
        return (delegate, relauncher, { spawned })
    }

    @Test func requestThenWillTerminateSpawnsOnce() {
        let (delegate, relauncher, spawned) = make()
        #expect(relauncher.request())
        #expect(spawned() == 0)
        delegate.applicationWillTerminate(Notification(name: NSNotification.Name("t")))
        delegate.applicationWillTerminate(Notification(name: NSNotification.Name("t")))
        #expect(spawned() == 1)
    }

    @Test func noRequestSpawnsNothing() {
        let (delegate, _, spawned) = make()
        delegate.applicationWillTerminate(Notification(name: NSNotification.Name("t")))
        #expect(spawned() == 0)
    }

    @Test func cancelledQuitClearsTheRequest() {
        var spawned = 0
        let relauncher = AppRelauncher(canSpawn: { true }, spawn: { spawned += 1 })
        let delegate = AppDelegate(environment: nil, relauncher: relauncher, sortRunningCheck: { true })
        var alerts = 0
        delegate.showSortRunningAlert = { alerts += 1 }
        relauncher.request()
        let reply = delegate.applicationShouldTerminate(NSApplication.shared)
        #expect(reply == .terminateCancel)
        #expect(alerts == 1)
        #expect(!relauncher.isRequested)
        // A later normal quit must not relaunch.
        delegate.applicationWillTerminate(Notification(name: NSNotification.Name("t")))
        #expect(spawned == 0)
    }

    @Test func missingOpenSetsNoRequest() {
        let (_, relauncher, _) = make(canSpawn: false)
        #expect(!relauncher.request())
        #expect(!relauncher.isRequested)
    }
}
