import AppKit

/// Owns the 1 app environment and the 1 `AppModel`, and stops a quit while a sort or an undo changes files
/// (final review M4). A quit in the middle of a copy leaves a part file that the journal does not know.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let sortRunningMessage = "A sort is running. Stop it first, then quit."

    /// Nil in the test host: tests make their own environment.
    let environment: AppEnvironment?
    let app: AppModel?

    /// The app: the bundled model, Application Support, and standard defaults. The test host must not read
    /// the real Application Support or standard defaults, so it gets no environment.
    override convenience init() {
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.init(environment: isTestHost ? nil : AppEnvironment())
    }

    init(environment: AppEnvironment?) {
        self.environment = environment
        app = environment.map { AppModel(environment: $0) }
        super.init()
    }

    /// True while a sort or an undo changes files.
    func isSortRunning() -> Bool {
        environment?.library.isSortRunning ?? false
    }

    /// The answer to a quit: cancel while a sort or an undo runs.
    static func terminateReply(sortIsRunning: Bool) -> NSApplication.TerminateReply {
        sortIsRunning ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reply = Self.terminateReply(sortIsRunning: isSortRunning())
        if reply == .terminateCancel {
            let alert = NSAlert()
            alert.messageText = Self.sortRunningMessage
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        return reply
    }
}
