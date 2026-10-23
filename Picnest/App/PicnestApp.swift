import SwiftUI

@main
struct PicnestApp: App {
    /// Owns the environment and the 1 `AppModel`, and asks before a quit during a sort.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 1 window (final review I1). ⌘N and window restore cannot open a second view of the 1 `AppModel`,
        // so 2 views cannot start 2 scans or sorts of the same session.
        Window("Picnest", id: "main") {
            Group {
                if let environment = delegate.environment, let app = delegate.app {
                    RootView(app: app, environment: environment)
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            // No File > New Window.
            CommandGroup(replacing: .newItem) {}
            ReviewCommands()
        }
    }
}
