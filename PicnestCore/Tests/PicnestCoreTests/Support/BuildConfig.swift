/// The build configuration of the test run. Timing tests run only in release builds.
enum BuildConfig {
    static var isRelease: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}
