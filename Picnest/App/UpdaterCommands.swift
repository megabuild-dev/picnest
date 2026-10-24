import Foundation
import Observation
import Sparkle
import SwiftUI

/// Mirrors `SPUUpdater.canCheckForUpdates` for the menu item (spec 8). Sparkle turns checks off while
/// a check runs, and the item must follow.
@MainActor
@Observable
final class UpdaterViewModel {
    private(set) var canCheckForUpdates: Bool

    /// The KVO subscription. Held so it stays alive, and released with this object.
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            // Sparkle changes this on the main thread. The hop keeps the code correct if that changes.
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }
}

/// Picnest > **Check for Updates…** (spec 8). Sparkle shows its own window, downloads the new version,
/// and replaces the app in `/Applications`.
struct CheckForUpdatesView: View {
    @State private var model: UpdaterViewModel

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _model = State(initialValue: UpdaterViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }
}
