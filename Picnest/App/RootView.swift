import PicnestCore
import SwiftUI

/// Shows the screen that `AppModel` selects.
struct RootView: View {
    let app: AppModel
    @State private var welcome: WelcomeViewModel

    private let environment: AppEnvironment

    init(app: AppModel, environment: AppEnvironment) {
        self.app = app
        self.environment = environment
        _welcome = State(initialValue: WelcomeViewModel(app: app, library: environment.library))
    }

    var body: some View {
        switch app.screen {
        case .welcome:
            WelcomeView(model: welcome)
        case .scanning(let url, let rescanOf):
            ScanView(app: app, scanService: environment.scanService, source: url, rescanOf: rescanOf,
                     openURL: { NSWorkspace.shared.open($0) })
                .id(url)
        case .review(let review, let afterScan):
            ReviewView(review: review, classify: environment.classifyService, thumbnails: environment.thumbnails,
                       sortService: environment.sortService, library: environment.library, app: app,
                       afterScan: afterScan)
                .id(ObjectIdentifier(review))
        }
    }
}
