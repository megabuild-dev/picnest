import AppKit
import SwiftUI

/// The layout editor (UI redesign, Phase 5): header, photo panel, page, settings panel, and bottom bar.
/// Every decision lives in `LayoutEditorViewModel`; this view only lays out and forwards.
struct LayoutEditorView: View {
    @Bindable var model: LayoutEditorViewModel
    let library: ReviewViewModel
    @State private var showsSettings = true
    @FocusState private var hasFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                if !model.isPreviewing { LayoutPhotoPanel(model: model, library: library) }
                center
                if !model.isPreviewing && showsSettings { LayoutSettingsPanel(model: model) }
            }
            Divider()
            LayoutBottomBar(model: model, showsSettings: $showsSettings)
        }
        .background(Theme.background.color)
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onAppear { hasFocus = true }
        .onKeyPress(phases: [.down, .repeat], action: handle)
        .alert("Could not export", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.exportError = nil }
        } message: {
            Text(model.exportError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text("Create Layout").font(.system(size: 17, weight: .bold))
                TextField("Layout name", text: Binding(get: { model.document.title }, set: model.setTitle))
                    .textFieldStyle(.plain).multilineTextAlignment(.center)
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
                    .frame(width: 220)
            }
            Spacer(minLength: 0)
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo).disabled(!model.canUndo)
            Button { model.togglePreview() } label: { Label("Preview", systemImage: "eye") }
                .accessibilityAddTraits(model.isPreviewing ? .isSelected : [])
            exportMenu
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var exportMenu: some View {
        Menu {
            Button("PNG…") { Task { await model.export(startingWith: .png) } }
            Button("PDF…") { Task { await model.export(startingWith: .pdf) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button).buttonStyle(.borderedProminent)
        .disabled(model.isExporting || model.document.photoIDs.isEmpty)
    }

    private var center: some View {
        VStack(spacing: 6) {
            LayoutCanvas(model: model)
            status
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var status: some View {
        if model.unavailableCount > 0 {
            Text(verbatim: CountText.leftOut(model.unavailableCount)).font(.system(size: 12))
                .foregroundStyle(Theme.needsReview.color)
        }
        if let used = model.usedText {
            Text(verbatim: used).font(.system(size: 13))
        }
        if let saved = model.savedText {
            HStack(spacing: 8) {
                Text(verbatim: saved)
                Button("Show in Finder", action: model.revealLastExport).buttonStyle(.link)
            }
            .font(.system(size: 12)).foregroundStyle(Theme.confirmed.color)
        } else {
            Text("The layout saves by itself. Export makes a PNG or PDF file. Your photos do not change.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
        }
    }

    /// The keys of the layout. A text field that has focus keeps them for itself.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !Self.isEditingText else { return .ignored }
        let plain = press.modifiers.isEmpty, option = press.modifiers == .option
        switch press.key {
        case .leftArrow where plain: model.moveSelection(by: -1)
        case .rightArrow where plain: model.moveSelection(by: 1)
        case .leftArrow where option: model.moveSelectedPhoto(by: -1)
        case .rightArrow where option: model.moveSelectedPhoto(by: 1)
        case .delete where plain, .deleteForward where plain: model.removeSelected()
        case .pageUp where plain: model.step(page: -1)
        case .pageDown where plain: model.step(page: 1)
        case .escape where plain: model.handleEscape()
        default: return .ignored
        }
        return .handled
    }

    private static var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSText }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })
    }
}
