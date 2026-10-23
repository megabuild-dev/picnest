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
                .foregroundStyle(.secondary)
            Picker("Kind", selection: $model.kind) {
                Text("Exact copies (\(model.exactCount))").tag(DuplicateGroup.Kind.exact)
                Text("Similar photos (\(model.similarCount))").tag(DuplicateGroup.Kind.similar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(groups) { group in
                        GroupCard(model: model, group: group) { isFocused = true }
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
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 1 group: the photos side by side, then **Not Duplicates** and **Move <N> to Trash**.
private struct GroupCard: View {
    let model: DuplicatesViewModel
    let group: DuplicateGroup
    /// Runs after a click, so the view takes the keyboard focus (Space and Return).
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(group.ids, id: \.self) { id in
                        DuplicateTile(model: model, id: id, isKeep: model.isKeep(id, in: group))
                            // Double-click first, so a double-click never changes Keep.
                            .onTapGesture(count: 2) { model.openPreview(id) }
                            .onTapGesture {
                                model.toggleKeep(id, in: group)
                                onTap()
                            }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
            HStack {
                Text("\(group.ids.count) photos")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Not Duplicates") { model.notDuplicates(group) }
                Button(model.trashTitle(of: group)) { Task { await model.trash(group) } }
                    .disabled(model.trashCount(of: group) == 0 || model.isCleaning)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }
}

/// 1 photo of a card: the thumbnail with the **Keep** badge, the file name, the pixel size and the file size.
private struct DuplicateTile: View {
    let model: DuplicatesViewModel
    let id: MediaID
    let isKeep: Bool

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        let tile = model.tile(id)
        let shape = RoundedRectangle(cornerRadius: ReviewStyle.tileCorner)
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { thumbnail }
                .overlay(alignment: .topLeading) { if isKeep { keepBadge } }
                .clipShape(shape)
                .contentShape(shape)
                .overlay {
                    shape.strokeBorder(isKeep ? ReviewStyle.green : Color.primary.opacity(0.1),
                                       lineWidth: isKeep ? 2.5 : 0.5)
                }
                .opacity(isKeep ? 1 : 0.8)
            Text(tile.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text([tile.pixelSize, tile.fileSize].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: DuplicatesViewModel.tileWidth)
        .contentShape(Rectangle())
        .task(id: id) { await load() }
        .help(isKeep ? "Keep. Click to unmark." : "Click to mark Keep.")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isKeep ? [.isImage, .isSelected] : .isImage)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            Rectangle().fill(.quaternary).overlay {
                if failed {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var keepBadge: some View {
        Text("Keep")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(ReviewStyle.green, in: Capsule())
            .padding(8)
    }

    private func load() async {
        let loaded = await model.thumbnail(id, maxPixel: DuplicatesViewModel.tileMaxPixel)
        guard !Task.isCancelled else { return }
        image = loaded
        failed = loaded == nil
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
