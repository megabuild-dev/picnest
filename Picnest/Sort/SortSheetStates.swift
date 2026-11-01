import AppKit
import SwiftUI

/// The running state of the Sort sheet: progress by file count and **Stop**.
struct SortRunningView: View {
    let model: SortViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.title)
                .font(.system(size: 18, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            SortCard {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.progress)
                        .tint(Theme.accent.color)
                        .accessibilityLabel(Text("Progress"))
                        .accessibilityValue(Text(verbatim: model.progressAccessibilityValue))
                    Label {
                        (model.isStopping ? Text("Stopping after the current file…") : Text(verbatim: model.progressText))
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: model.isStopping ? "pause.circle" : "arrow.triangle.2.circlepath")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary.color)
                }
            }
            HStack {
                Spacer()
                Button(action: model.stop) { Label("Stop", systemImage: "stop.circle") }
                    .disabled(model.isStopping)
                    .controlSize(.large)
                    .accessibilityLabel(Text("Stop"))
                    .accessibilityHint(Text("Stopping after the current file…"))
            }
        }
    }
}

/// The summary state: finished, stopped or failed, with **Show in Finder** and **Undo Last Sort**.
struct SortSummaryView: View {
    let model: SortViewModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SortCard(stroke: icon.color.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon.name)
                            .font(.system(size: 26))
                            .foregroundStyle(icon.color)
                            .accessibilityHidden(true)
                        Text(model.summaryText)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    if let warning = model.saveWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.destructive.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if model.isUndoing { ProgressView().controlSize(.small) }
            if model.canUndoLastSort {
                Button(action: model.undoLastSort) { Label("Undo Last Sort", systemImage: "arrow.uturn.backward") }
                    .disabled(model.isBusy)
            }
            Spacer()
            if case .failed = model.state {
                Button("Back", action: model.backToOptions).disabled(model.isUndoing)
            } else if model.canShowInFinder {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([model.options.destination])
                } label: { Label("Show in Finder", systemImage: "folder") }
            }
            Button("Done") {
                dismiss()
                model.done()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent.color)
            .disabled(model.isBusy)
        }
        .controlSize(.large)
    }

    private var icon: (name: String, color: Color) {
        switch model.state {
        case .finished: ("checkmark.circle.fill", Theme.confirmed.color)
        case .stopped: ("pause.circle.fill", Theme.needsReview.color)
        default: ("exclamationmark.triangle.fill", Theme.destructive.color)
        }
    }
}
