import PicnestCore
import SwiftUI

/// Scan screen (spec 3.2): a centered card with the progress, the time left, and **Cancel**.
struct ScanView: View {
    @State private var model: ScanViewModel

    /// The view model is made once per screen, in the `@State` initializer.
    init(app: AppModel, scanService: ScanService, source: URL, rescanOf: Session? = nil,
         openURL: @escaping (URL) -> Void) {
        _model = State(initialValue: ScanViewModel(
            app: app, scanService: scanService, source: source, rescanOf: rescanOf, openURL: openURL))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(model.folderName).font(.title2.weight(.semibold))
            content
        }
        .padding(32)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .preparingModel, .embedding:
            VStack(spacing: 10) {
                Text(model.message).foregroundStyle(.secondary)
                if let fraction = model.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                if let count = model.countText {
                    Text(count).monospacedDigit()
                }
                if let eta = model.etaText {
                    Text(eta).font(.callout).foregroundStyle(.secondary)
                }
            }
            Button("Cancel", action: model.cancel).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
        case .empty:
            Text(model.message)
            Button("Choose Another Folder", action: model.chooseAnotherFolder).buttonStyle(.borderedProminent)
        case .permissionDenied:
            Text(model.message)
            Text("Allow access in System Settings, then choose the folder again.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Back", action: model.back).buttonStyle(.bordered)
                Button("Open System Settings", action: model.openSystemSettings).buttonStyle(.borderedProminent)
            }
        case .failed:
            Text(model.message).multilineTextAlignment(.center)
            Button("Back", action: model.back).buttonStyle(.borderedProminent)
        }
    }
}
