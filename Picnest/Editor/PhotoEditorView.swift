import SwiftUI

/// The photo editor (UI redesign, Phase 4): header, tool rail, canvas, panel, and filmstrip.
/// Every decision lives in `PhotoEditorViewModel`; this view only lays out and forwards.
struct PhotoEditorView: View {
    @Bindable var model: PhotoEditorViewModel
    let library: ReviewViewModel
    @State private var isShowingInfo = false
    @FocusState private var hasFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                EditorToolRail(model: model)
                center
                EditorPanel(model: model)
            }
            Divider()
            EditorFilmstrip(model: model, library: library)
        }
        .background(Theme.background.color)
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onAppear { hasFocus = true }
        // The arrow keys and Esc reach here only when no slider has taken them.
        .onKeyPress(.leftArrow) { model.step(by: -1); return .handled }
        .onKeyPress(.rightArrow) { model.step(by: 1); return .handled }
        .onKeyPress(.escape) { model.requestClose(); return .handled }
        .confirmationDialog("Discard your edits?", isPresented: discardBinding, titleVisibility: .visible) {
            Button("Discard Edits", role: .destructive) { model.confirmDiscard() }
            Button("Cancel", role: .cancel) { model.cancelDiscard() }
        } message: {
            Text("The edits to this photo are not exported yet.")
        }
        .alert("Could not export", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.exportError = nil }
        } message: {
            Text(model.exportError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Edit Photo").font(.system(size: 22, weight: .bold))
            Text("Original stays unchanged").font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
            Button { isShowingInfo.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary.color)
                .accessibilityLabel(Text("About exporting"))
                .popover(isPresented: $isShowingInfo) {
                    Text("Export edited copy saves a new file. The original photo never changes.")
                        .padding(12).frame(width: 260)
                }
            Spacer(minLength: 0)
            Button("Reset", systemImage: "arrow.counterclockwise", action: model.reset)
                .disabled(!model.hasChanges)
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(!model.canUndo)
            Button { Task { await model.export() } } label: {
                Label("Export edited copy", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.isExporting)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private var center: some View {
        VStack(spacing: 6) {
            EditorCanvas(model: model)
                .overlay(alignment: .bottomTrailing) { showOriginal.padding(12) }
            Text(verbatim: model.statusText).font(.system(size: 13))
            if let saved = model.savedText {
                HStack(spacing: 8) {
                    Text(verbatim: saved)
                    Button("Show in Finder", action: model.revealLastExport).buttonStyle(.link)
                }
                .font(.system(size: 12)).foregroundStyle(Theme.confirmed.color)
            } else {
                Text("Edited copy will be exported separately")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    /// Hold to see the photo with no edit.
    private var showOriginal: some View {
        Label("Show Original", systemImage: "eye")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.onBadge.color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.badgeBackground.color.opacity(Theme.badgeAlpha), in: Capsule())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 50, perform: {}, onPressingChanged: {
                model.isShowingOriginal = $0
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Show Original"))
            .accessibilityAction { model.isShowingOriginal.toggle() }
    }

    /// Esc or a click outside counts as Cancel, so the pending item clears.
    private var discardBinding: Binding<Bool> {
        Binding(get: { model.isConfirmingDiscard },
                set: { if !$0 && model.isConfirmingDiscard { model.cancelDiscard() } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })
    }
}
