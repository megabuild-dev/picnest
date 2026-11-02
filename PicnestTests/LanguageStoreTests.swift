import Testing
@testable import Picnest

/// The System, English, and Tiếng Việt language setting. Uses an isolated suite, never the real `AppleLanguages`.
@MainActor
struct LanguageStoreTests {
    @Test func testDefaultIsSystem() {
        let suite = TestDefaults()
        #expect(LanguageStore(defaults: suite.defaults, domain: suite.name).language == .system)
    }

    @Test func testSetViWritesAppleLanguages() {
        let suite = TestDefaults()
        let store = LanguageStore(defaults: suite.defaults, domain: suite.name)
        store.language = .vi
        #expect(suite.defaults.persistentDomain(forName: suite.name)?["AppleLanguages"] as? [String] == ["vi"])
        #expect(LanguageStore(defaults: suite.defaults, domain: suite.name).language == .vi)
    }

    @Test func testSetSystemRemovesKey() {
        let suite = TestDefaults()
        let store = LanguageStore(defaults: suite.defaults, domain: suite.name)
        store.language = .en
        store.language = .system
        #expect(suite.defaults.persistentDomain(forName: suite.name)?["AppleLanguages"] == nil)
    }

    @Test func testUnknownCodeFallsBackToSystem() {
        let suite = TestDefaults()
        suite.defaults.set(["xx"], forKey: "AppleLanguages")
        #expect(LanguageStore(defaults: suite.defaults, domain: suite.name).language == .system)
    }

    @Test func testNeedsRestartOnlyAfterChange() {
        let suite = TestDefaults()
        let store = LanguageStore(defaults: suite.defaults, domain: suite.name)
        #expect(!store.needsRestart)
        store.language = .vi
        #expect(store.needsRestart)
        store.language = .system
        #expect(!store.needsRestart)
    }
}
