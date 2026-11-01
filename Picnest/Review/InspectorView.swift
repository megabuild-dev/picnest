import PicnestCore
import SwiftUI

/// The panel at the right (spec 4.2): the facts and actions of 1 selected photo, the count and the batch
/// actions for more, the facts of the open category with no photo selected, or a hint.
struct InspectorView: View {
    let model: ReviewViewModel

    init(model: ReviewViewModel) { self.model = model }

    var body: some View {
        Group {
            switch model.inspectorContent {
            case .many(let count):
                ManyPhotos(model: model, count: count)
            case .photo(let facts):
                ScrollView {
                    SinglePhoto(model: model, facts: facts)
                        // A new id makes a new view, so both .task loads of the old photo are cancelled.
                        .id(facts.id)
                        .padding(16)
                }
            case .category(let facts):
                CategoryDetails(model: model, facts: facts)
            case .hint:
                Text("Select a photo to see its details.")
                    .foregroundStyle(Theme.textSecondary.color)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 260, idealWidth: 300)
        .background(Theme.surface.color)
    }
}

/// The open category with no photo selected: icon, name, photo count, and the folder name (read-only).
private struct CategoryDetails: View {
    let model: ReviewViewModel
    let facts: CategoryFacts

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: facts.emoji)
                .font(.system(size: 36))
                .frame(width: 64, height: 64)
                .background(Theme.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            Text(verbatim: facts.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary.color)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 8) {
                row("Photos") { Text(CountText.photos(facts.photoCount)) }
                row("Folder") { Text(verbatim: facts.folderName).textSelection(.enabled) }
            }
            Button("Reveal in Finder") { model.showCategoryInFinder(facts.id) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(!facts.canReveal)
            Text("Select a photo to see its details.")
                .foregroundStyle(Theme.textSecondary.color)
            Spacer()
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func row(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.textSecondary.color)
            Spacer(minLength: 8)
            value().multilineTextAlignment(.trailing)
        }
    }
}

private struct ManyPhotos: View {
    let model: ReviewViewModel
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CountText.photosSelected(count))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary.color)
            SelectionActions(model: model)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

private struct SinglePhoto: View {
    let model: ReviewViewModel
    let facts: InspectorFacts
    @State private var image: CGImage?
    @State private var pixels: PixelSize?
    @State private var anchor = ShareAnchor()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: facts.name)
                    .font(.system(size: 15, weight: .bold))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if model.bodyKind != .recentlyDeleted { FavoriteButton(model: model, id: facts.id) }
            }
            VStack(alignment: .leading, spacing: 8) {
                row("Category") { status }
                row("Date") {
                    if let date = facts.date { Text(date, format: .dateTime.day().month(.abbreviated).year()) }
                    else { Text("no date") }
                }
                row("Dimensions") {
                    if let pixels { Text(verbatim: "\(pixels.width.formatted()) × \(pixels.height.formatted())") }
                    else { Text(verbatim: "—") }
                }
                row("File size") { Text(facts.fileSize, format: .byteCount(style: .file)) }
                row("Confidence") { confidence }
            }
            if let suggestion = facts.suggestion { suggestionBlock(suggestion) }
            actions
        }
        .font(.system(size: 13))
        .task { image = await model.thumbnail(facts.id, maxPixel: 800) }
        .task { pixels = await model.pixelSize(of: facts.id) }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner).fill(Theme.placeholderFill.color)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner))
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .background { ShareAnchorView(anchor: anchor) }
    }

    private func row(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.textSecondary.color)
            Spacer(minLength: 8)
            value().multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var status: some View {
        switch facts.status {
        case .category(let emoji, let name): Text(verbatim: "\(emoji) \(name)")
        case .notSure: Text("Needs Review").foregroundStyle(Theme.needsReview.color)
        case .staysHere: Text("Don't move")
        case .none: Text(verbatim: "—")
        }
    }

    @ViewBuilder private var confidence: some View {
        if facts.isChosenByYou {
            Text("Chosen by you").foregroundStyle(Theme.confirmed.color)
        } else if let percent = facts.confidence {
            HStack(spacing: 8) {
                ConfidenceBar(fraction: Double(percent) / 100, isUncertain: facts.isUncertain)
                Text(verbatim: "\(percent)%").monospacedDigit()
            }
        } else {
            Text(verbatim: "—")
        }
    }

    private func suggestionBlock(_ suggestion: InspectorFacts.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Suggested category") { Text(verbatim: suggestion.categoryName).fontWeight(.semibold) }
            if let alternative = suggestion.alternativeName {
                row("Alternative category") {
                    if let percent = suggestion.alternativePercent { Text("\(alternative) \(percent)%") }
                    else { Text(verbatim: alternative) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.needsReview.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var actions: some View {
        if model.bodyKind == .recentlyDeleted {
            Button("Put Back", systemImage: "arrow.uturn.backward", action: model.putBackSelection)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        } else {
            libraryActions
        }
    }

    private var libraryActions: some View {
        HStack(spacing: 8) {
            if facts.isUncertain {
                Button("Accept suggestion", systemImage: "checkmark", action: model.acceptSelection)
                    .tint(Theme.accent.color)
                Menu("Choose category…") { MoveToMenuItems(model: model) }
                    .menuStyle(.button).fixedSize()
            } else {
                Menu("Move to…") { MoveToMenuItems(model: model) }
                    .menuStyle(.button).fixedSize()
            }
            Menu("More", systemImage: "ellipsis") { PhotoContextMenu(model: model, id: facts.id, anchor: anchor.view) }
                .menuStyle(.button).labelStyle(.iconOnly).fixedSize()
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
}

/// A thin bar from 0 to 1. Amber for an uncertain guess, green for a confident one.
private struct ConfidenceBar: View {
    let fraction: Double
    let isUncertain: Bool

    var body: some View {
        Capsule().fill(Theme.placeholderFill.color)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill((isUncertain ? Theme.needsReview : Theme.confirmed).color)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(minWidth: 60)
    }
}

#if DEBUG
#Preview("One photo", traits: .fixedLayout(width: 300, height: 640)) {
    let model = ReviewViewModel(
        review: ReviewPreviewData.review(), classify: ClassifyService(),
        thumbnails: ThumbnailService(images: ImageRepository()), library: ReviewPreviewData.library(),
        app: ReviewPreviewData.app(), onRescan: {})
    model.selectedItem = .notSure
    if let first = model.visibleIDs.first { model.click(first, modifiers: []) }
    return InspectorView(model: model)
}
#endif
