import PicnestCore
import QuickLook
import SwiftUI

/// The Duplicates view (spec 3.6, look of section 6.1): a notice line, the **Exact copies** / **Similar
/// photos** segments, and 1 card per group with the photos side by side. A click on a tile marks or unmarks
/// Keep. Space, Return and double-click open Quick Look.
struct DuplicatesView: View {
    @Bindable var model: DuplicatesViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        content
            .task { await model.find() }
            .quickLookPreview($model.previewURL, in: model.previewURLs)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .finding:
            FindingView(state: model.state)
        case .failed(let message):
            ContentUnavailableView("Could Not Look for Duplicates", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .empty:
            ContentUnavailableView(DuplicatesViewModel.emptyText, systemImage: "square.on.square")
        case .ready:
            groupsList
        }
    }

    private var groupsList: some View {
        let groups = model.groups
        return VStack(alignment: .leading, spacing: 12) {
            Label(DuplicatesViewModel.notice, systemImage: "info.circle")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary.color)
            Picker("Kind", selection: $model.kind) {
                Text("Exact copies (\(model.exactCount))").tag(DuplicateGroup.Kind.exact)
                Text("Similar photos (\(model.similarCount))").tag(DuplicateGroup.Kind.similar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Kind of duplicates")
            .fixedSize()
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(groups) { group in
                        DuplicateGroupCard(model: model, group: group) { isFocused = true }
                    }
                }
                .padding(.bottom, 20)
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView(DuplicatesViewModel.emptyText, systemImage: "square.on.square")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .background(Theme.background.color)
        .tint(Theme.accent.color)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            guard model.anchor != nil else { return .ignored }
            model.openPreview()
            return .handled
        }
    }
}

/// The progress while the app looks for duplicates.
private struct FindingView: View {
    let state: DuplicatesViewModel.State

    var body: some View {
        VStack(spacing: 10) {
            Text("Looking for duplicates…").font(.system(size: 13, weight: .semibold))
            if case .finding(let done, let total) = state, total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .frame(width: 280)
                Text("\(done.formatted()) / \(total.formatted())")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary.color)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// **Clean Up All** in the toolbar, with the total count and a confirmation (spec 3.6).
struct CleanUpAllButton: View {
    let model: DuplicatesViewModel
    @State private var isConfirming = false

    var body: some View {
        Button(model.cleanUpTitle, systemImage: "trash") { isConfirming = true }
            .labelStyle(.titleAndIcon)
            .disabled(model.cleanUpCount == 0 || model.isCleaning)
            .help("Move the photos that are not marked Keep to the Trash")
            .confirmationDialog(model.cleanUpConfirmation, isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) { Task { await model.cleanUpAll() } }
                    .disabled(model.isCleaning)
                Button("Cancel", role: .cancel) {}
            }
    }
}

#if DEBUG
#Preview("Duplicates", traits: .fixedLayout(width: 1000, height: 700)) {
    let review = ReviewPreviewData.review()
    let model = DuplicatesViewModel(review: review, thumbnail: { _, _ in nil }, onTrashErrors: { _ in })
    model.showForPreview([
        DuplicateGroup(kind: .exact, ids: ["IMG_5500.HEIC", "IMG_5503.HEIC"], keepIDs: ["IMG_5500.HEIC"]),
        DuplicateGroup(kind: .similar, ids: ["z7913505267101_a3f.jpg", "z7913505267102_a3f.jpg",
                                             "z7913505267104_a3f.jpg"],
                       keepIDs: ["z7913505267101_a3f.jpg"]),
    ])
    return DuplicatesView(model: model).background(.background)
}
#endif
