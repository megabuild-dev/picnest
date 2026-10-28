import Observation
import SwiftUI

/// Mirrors `AppUpdater.canCheckForUpdates` for the menu item (spec 8). Sparkle turns checks off while
/// a check runs, and the item must follow.
@MainActor
@Observable
final class UpdaterViewModel {
    private(set) var canCheckForUpdates: Bool

    @ObservationIgnored private let updater: any AppUpdater

    /// The subscription. Held so it stays alive, and released with this object.
    @ObservationIgnored private var observation: AnyObject?

    init(updater: any AppUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observeCanCheckForUpdates { [weak self] canCheck in
            self?.canCheckForUpdates = canCheck
        }
    }

    /// The user chose **Check for Updates…**.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// Picnest > **Check for Updates…** (spec 8). Sparkle shows its own window, downloads the new version,
/// and replaces the app in `/Applications`.
struct CheckForUpdatesView: View {
    @State private var model: UpdaterViewModel

    init(updater: any AppUpdater) {
        _model = State(initialValue: UpdaterViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { model.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }
}
