import PicnestCore
import SwiftUI

/// The panel at the right (spec 4.2): a hint with no photo selected, the facts and actions of 1 selected
/// photo, or the count and the batch actions for more.
struct InspectorView: View {
    let model: ReviewViewModel

    init(model: ReviewViewModel) { self.model = model }

    var body: some View {
        let selection = model.selection
        Group {
            if selection.count > 1 {
                ManyPhotos(model: model, count: selection.count)
            } else if let id = selection.first, let facts = model.inspectorFacts(for: id) {
                ScrollView {
                    SinglePhoto(model: model, facts: facts)
                        // A new id makes a new view, so both .task loads of the old photo are cancelled.
                        .id(id)
                        .padding(16)
                }
            } else {
                Text("Select a photo to see its details.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 260, idealWidth: 300)
        .background(Theme.surface.color)
    }
}

private struct ManyPhotos: View {
    let model: ReviewViewModel
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(count) photos selected")
                .font(.system(size: 15, weight: .bold))
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
            Text(verbatim: facts.name)
                .font(.system(size: 15, weight: .bold))
                .textSelection(.enabled)
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
            RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner).fill(.quaternary)
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
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value().multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var status: some View {
        switch facts.status {
        case .category(let emoji, let name): Text(verbatim: "\(emoji) \(name)")
        case .notSure: Text("Needs Review").foregroundStyle(Theme.needsReview.color)
        case .staysHere: Text("Stays here")
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

    private var actions: some View {
        HStack(spacing: 8) {
            if facts.isUncertain {
                Button("Accept suggestion", systemImage: "checkmark", action: model.acceptSelection)
                    .tint(.accentColor)
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
        Capsule().fill(.quaternary)
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
