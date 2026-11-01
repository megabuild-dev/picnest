import AppKit
import Testing
@testable import Picnest

/// Spec 4.1: the System, Light, and Dark appearance setting.
@MainActor
struct AppearanceStoreTests {
    @Test func testDefaultIsSystem() {
        let suite = TestDefaults()
        #expect(AppearanceStore(defaults: suite.defaults).mode == .system)
    }

    @Test func testSetModeSavesAndReloads() {
        let suite = TestDefaults()
        let store = AppearanceStore(defaults: suite.defaults)
        defer { NSApp?.appearance = nil }
        store.mode = .dark
        #expect(suite.defaults.string(forKey: "appearance") == "dark")
        #expect(AppearanceStore(defaults: suite.defaults).mode == .dark)
    }

    @Test func testUnknownRawValueFallsBackToSystem() {
        let suite = TestDefaults()
        suite.defaults.set("sepia", forKey: "appearance")
        #expect(AppearanceStore(defaults: suite.defaults).mode == .system)
    }

    @Test func testSystemHasNilAppearance() {
        #expect(AppearanceMode.system.nsAppearance == nil)
    }

    @Test func testLightAndDarkAppearanceNames() {
        #expect(AppearanceMode.light.nsAppearance?.name == .aqua)
        #expect(AppearanceMode.dark.nsAppearance?.name == .darkAqua)
    }
}
