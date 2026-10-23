import AppKit
import PicnestCore
import SwiftUI
import UniformTypeIdentifiers

/// The Sort sheet (spec 3.5, mockup `sheet-v4.html`): options and a preview, then progress, then a summary.
struct SortSheet: View {
    @Bindable var model: SortViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingDestination = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .editing, .confirmingMove: editing
            case .running: running
            case .finished, .stopped, .failed: summary
            }
        }
        .padding(22)
        .frame(width: 470)
        .interactiveDismissDisabled(model.isBusy)
        .confirmationDialog(model.confirmMoveTitle, isPresented: confirmingMove, titleVisibility: .visible) {
            Button("Move", role: .destructive, action: model.confirmMove)
            Button("Cancel", role: .cancel, action: model.cancelMove)
        } message: {
            Text(model.confirmMoveMessage)
        }
        .fileImporter(isPresented: $isChoosingDestination, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setDestination(url) }
        }
    }

    private var confirmingMove: Binding<Bool> {
        Binding(get: { model.state == .confirmingMove }, set: { if !$0 { model.cancelMove() } })
    }

    // MARK: - Editing

    @ViewBuilder private var editing: some View {
        Text(model.title).font(.system(size: 18, weight: .bold))
        Text(model.subtitle ?? " ")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .padding(.bottom, 14)

        destinationRow
        if let note = model.destinationNote {
            Text(note).font(.system(size: 12)).foregroundStyle(.red).padding(.top, 4)
        }

        VStack(spacing: 8) {
            ChoiceCard(title: "Copy", detail: "Originals stay in the source folder.",
                       isOn: model.options.mode == .copy) { model.options.mode = .copy }
            ChoiceCard(title: "Move", detail: SortViewModel.moveDetail,
                       isOn: model.options.mode == .move) { model.options.mode = .move }
        }
        .padding(.top, 12)

        VStack(alignment: .leading, spacing: 8) {
            Toggle("Make date sub-folders (year / month)", isOn: $model.options.dateFolders)
            Toggle("Rename files to date + category + number", isOn: $model.options.rename)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 10)

        if model.showSuggestHint {
            HStack(spacing: 6) {
                Text(model.suggestHintText).font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Suggest Categories…", action: model.suggestFromSort).buttonStyle(.link)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }

        if model.showNotSureChoice {
            Text(model.notSureHeader).fontWeight(.semibold).padding(.top, 2).padding(.bottom, 6)
            VStack(spacing: 8) {
                notSureCard(.acceptBestGuess, "Accept best guess", "Put each one in its most likely category.")
                notSureCard(.notSureFolder, "Put in a \"Not sure\" folder", "Sort them by hand later in Finder.")
                notSureCard(.leaveInSource, "Leave in the source folder", "Do not copy or move them.")
            }
        }

        PreviewTree(lines: model.previewLines)
            .opacity(model.isPlanning ? 0.5 : 1)
            .padding(.top, 10)
            .padding(.bottom, 16)

        if let notice = model.notice {
            Label(notice, systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(ReviewStyle.amber)
                .padding(.bottom, 10)
        }

        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(model.sortButtonTitle, action: model.sort)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSort)
        }
        .controlSize(.large)
    }

    private var destinationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(model.destinationText)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.destinationText)
            Spacer(minLength: 8)
            Button("Change…") { isChoosingDestination = true }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func notSureCard(_ choice: NotSureChoice, _ title: String, _ detail: String) -> some View {
        ChoiceCard(title: title, detail: detail, isOn: model.options.notSureChoice == choice) {
            model.options.notSureChoice = choice
        }
    }

    // MARK: - Running

    @ViewBuilder private var running: some View {
        Text(model.title).font(.system(size: 18, weight: .bold)).padding(.bottom, 16)
        ProgressView(value: model.progress)
        Text(model.isStopping ? "Stopping after the current file…" : model.progressText)
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .padding(.bottom, 16)
        HStack {
            Spacer()
            Button("Stop", action: model.stop)
                .disabled(model.isStopping)
                .controlSize(.large)
        }
    }

    // MARK: - Summary

    @ViewBuilder private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summaryIcon.name)
                .font(.system(size: 28))
                .foregroundStyle(summaryIcon.color)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.summaryText)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = model.saveWarning {
                    Text(warning)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, 20)

        HStack(spacing: 10) {
            if model.isUndoing { ProgressView().controlSize(.small) }
            if model.canUndoLastSort {
                Button("Undo Last Sort", action: model.undoLastSort).disabled(model.isBusy)
            }
            Spacer()
            if case .failed = model.state {
                Button("Back", action: model.backToOptions).disabled(model.isUndoing)
            } else if model.canShowInFinder {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.options.destination])
                }
            }
            Button("Done") {
                dismiss()
                model.done()
            }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        }
        .controlSize(.large)
    }

    private var summaryIcon: (name: String, color: Color) {
        switch model.state {
        case .finished: ("checkmark.circle.fill", ReviewStyle.green)
        case .stopped: ("pause.circle.fill", ReviewStyle.amber)
        default: ("exclamationmark.triangle.fill", ReviewStyle.amber)
        }
    }
}

/// A radio choice as a card: a soft accent fill and ring when selected (mockup `.opt`).
private struct ChoiceCard: View {
    let title: String
    let detail: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.6), lineWidth: isOn ? 5 : 1.5)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isOn ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if isOn { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The folder tree preview (mockup `.tree`). The first line is the destination; counts are secondary.
private struct PreviewTree: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

#if DEBUG
/// The sheet in the editing state, over the fake review data (no files on disk).
private struct SortSheetPreview: View {
    @State private var model = SortViewModel(
        review: ReviewPreviewData.review(), sortService: SortService(), library: ReviewPreviewData.library())

    var body: some View {
        SortSheet(model: model).task { await model.load() }
    }
}

#Preview("Sort sheet") {
    SortSheetPreview()
}
#endif
