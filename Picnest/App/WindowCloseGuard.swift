import AppKit
import SwiftUI

/// Asks before the window closes (⌘W, the red button). SwiftUI keeps its own window delegate, so this one
/// wraps it: `allow` runs first, then the original delegate answers. `allow` is the same check as the quit
/// (`AppDelegate.confirmLeaving`), so a close cannot drop an export or an edit that a quit would keep.
@MainActor
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var original: (any NSWindowDelegate)?
    private let allow: () -> Bool

    init(allow: @escaping () -> Bool) { self.allow = allow }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard allow() else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }

    /// Puts this delegate in front of the current delegate of `window`, once.
    func install(on window: NSWindow) {
        guard window.delegate !== self else { return }
        original = window.delegate
        window.delegate = self
    }
}

/// Place it in the background of the window content.
struct WindowCloseGuard: NSViewRepresentable {
    let allow: () -> Bool

    func makeCoordinator() -> WindowCloseDelegate { WindowCloseDelegate(allow: allow) }

    func makeNSView(context: Context) -> NSView { Installer(delegate: context.coordinator) }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class Installer: NSView {
        let delegate: WindowCloseDelegate
        init(delegate: WindowCloseDelegate) {
            self.delegate = delegate
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            if let window { delegate.install(on: window) }
        }
    }
}
