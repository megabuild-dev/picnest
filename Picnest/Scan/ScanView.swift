import PicnestCore
import SwiftUI

/// Scan screen (spec 3.2): a centered card with the folder, found count, progress, time left, and **Cancel**.
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
            VStack(spacing: 4) {
                Text(model.folderName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.color)
                Text(model.folderPath)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            content
        }
        .padding(32)
        .frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.textSecondary.color.opacity(0.18)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.color)
        .tint(Theme.accent.color)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .preparingModel, .embedding:
            VStack(spacing: 10) {
                Text(model.message).foregroundStyle(Theme.textSecondary.color)
                if let fraction = model.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                if let found = model.foundText {
                    Text(found).font(.headline).monospacedDigit()
                }
                if let count = model.countText {
                    Text(count).monospacedDigit().foregroundStyle(Theme.textSecondary.color)
                }
                if let eta = model.etaText {
                    Text(eta).font(.callout).foregroundStyle(Theme.textSecondary.color)
                }
            }
            Button("Cancel", action: model.cancel).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
            Text("Cancel keeps your photos and the cache. Nothing is deleted.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary.color)
                .multilineTextAlignment(.center)
        case .empty:
            Text(model.message)
            Button("Choose Another Folder", action: model.chooseAnotherFolder).buttonStyle(.borderedProminent)
        case .permissionDenied:
            Text(model.message)
            Text("Allow access in System Settings, then choose the folder again.")
                .font(.callout).foregroundStyle(Theme.textSecondary.color)
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
