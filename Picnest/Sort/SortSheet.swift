import AppKit
import PicnestCore
import SwiftUI
import UniformTypeIdentifiers

/// The Sort sheet (spec 3.5, UI redesign 4.3): options and a preview, then progress, then a summary.
struct SortSheet: View {
    @Bindable var model: SortViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingDestination = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .editing, .confirmingMove: editing
            case .running: SortRunningView(model: model)
            case .finished, .stopped, .failed: SortSummaryView(model: model, dismiss: dismiss.callAsFunction)
            }
        }
        .padding(22)
        .frame(width: 470)
        .background(Theme.background.color)
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title).font(.system(size: 18, weight: .bold))
                Text(model.subtitle ?? " ")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary.color)
            }
            .fixedSize(horizontal: false, vertical: true)

            destinationSection
            modeSection
            optionsSection
            if model.showSuggestHint { suggestHint }
            if model.showNotSureChoice { needsReviewSection }
            previewSection

            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.needsReview.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SortCard {
                HStack(spacing: 10) {
                    Image(systemName: "folder").foregroundStyle(Theme.textSecondary.color)
                        .accessibilityHidden(true)
                    Text(model.destinationText)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.destinationText)
                    Spacer(minLength: 8)
                    Button("Change…") { isChoosingDestination = true }
                        .buttonStyle(.link)
                }
            }
            if let note = model.destinationNote {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.destructive.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modeSection: some View {
        let isMove = model.options.mode == .move
        return SortCard(stroke: isMove ? Theme.destructive.color.opacity(0.6) : Theme.textSecondary.color.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(selection: $model.options.mode) {
                    Text("Copy").tag(SortMode.copy)
                    Text("Move").tag(SortMode.move)
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
                if isMove {
                    Label(SortViewModel.moveDetail, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.destructive.color)
                } else {
                    Label("Originals stay in the source folder.", systemImage: "doc.on.doc")
                        .foregroundStyle(Theme.textSecondary.color)
                }
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optionsSection: some View {
        SortCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Make date sub-folders (year / month)", isOn: $model.options.dateFolders)
                Toggle("Rename files to date + category + number", isOn: $model.options.rename)
            }
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var suggestHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb").foregroundStyle(Theme.textSecondary.color).accessibilityHidden(true)
            Text(model.suggestHintText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
            Button("Suggest Categories…", action: model.suggestFromSort).buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var needsReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.notSureHeader, systemImage: "questionmark.circle")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.needsReview.color)
                .fixedSize(horizontal: false, vertical: true)
            reviewCard(.acceptBestGuess, "Accept best guess", "Put each one in its most likely category.")
            reviewCard(.notSureFolder, "Put in a \"Not sure\" folder", "Sort them by hand later in Finder.")
            reviewCard(.leaveInSource, "Leave in the source folder", "Do not copy or move them.")
        }
    }

    private func reviewCard(_ choice: NotSureChoice, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        ChoiceCard(title: Text(title), detail: Text(detail), isOn: model.options.notSureChoice == choice) {
            model.options.notSureChoice = choice
        }
    }

    private var previewSection: some View {
        PreviewTree(lines: model.previewLines).opacity(model.isPlanning ? 0.5 : 1)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(action: model.sort) {
                if model.options.mode == .move {
                    Label(model.sortButtonTitle, systemImage: "arrow.right.circle")
                } else {
                    Label(model.sortButtonTitle, systemImage: "square.and.arrow.down.on.square")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(model.options.mode == .move ? Theme.destructive.color : Theme.accent.color)
            .disabled(!model.canSort)
        }
        .controlSize(.large)
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
