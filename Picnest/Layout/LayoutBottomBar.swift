import SwiftUI

/// The bottom bar: the photo count, the page steps, the zoom, **Fit Page**, and the toggle of the settings panel.
struct LayoutBottomBar: View {
    @Bindable var model: LayoutEditorViewModel
    @Binding var showsSettings: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: model.countText).font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
            Spacer(minLength: 0)
            pageSteps
            Spacer(minLength: 0)
            zoom
            Button("Fit Page", action: model.zoomToFit).keyboardShortcut("0", modifiers: .command)
            Divider().frame(height: 16)
            Button { showsSettings.toggle() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.plain)
                .disabled(model.isPreviewing)
                .accessibilityLabel(Text("Settings"))
                .accessibilityAddTraits(showsSettings ? .isSelected : [])
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(Theme.background.color)
    }

    private var pageSteps: some View {
        HStack(spacing: 8) {
            Button { model.step(page: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canStepBack).accessibilityLabel(Text("Previous Page"))
            Text(verbatim: model.pageText).font(.system(size: 13)).monospacedDigit()
            Button { model.step(page: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canStepForward).accessibilityLabel(Text("Next Page"))
        }
        .buttonStyle(.plain)
    }

    private var zoom: some View {
        HStack(spacing: 8) {
            Button { model.zoomOut() } label: { Image(systemName: "minus.circle") }
                .keyboardShortcut("-", modifiers: .command).accessibilityLabel(Text("Zoom Out"))
            Text(verbatim: model.zoomText).font(.system(size: 13)).monospacedDigit()
                .frame(minWidth: 44).accessibilityLabel(Text("Zoom"))
            Button { model.zoomIn() } label: { Image(systemName: "plus.circle") }
                .keyboardShortcut("+", modifiers: .command).accessibilityLabel(Text("Zoom In"))
        }
        .buttonStyle(.plain)
    }
}
