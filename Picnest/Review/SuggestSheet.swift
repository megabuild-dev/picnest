import PicnestCore
import SwiftUI

/// The Suggest Categories sheet (spec 3.7): "Looking for groups…", then 1 row per group with a check box,
/// an emoji, a name, the photo count and 4 thumbnails, then **Add <N> Categories**.
struct SuggestSheet: View {
    @Bindable var model: SuggestViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suggest Categories").font(.system(size: 18, weight: .bold))
            content
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if model.state == .ready {
                    Button(model.addTitle, action: model.add)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canAdd)
                }
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 560)
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Looking for groups…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .empty:
            Text(SuggestViewModel.emptyText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                .multilineTextAlignment(.center)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(ReviewStyle.amber)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        case .ready:
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($model.rows) { $row in
                        SuggestRowView(model: model, row: $row)
                    }
                }
            }
            .frame(maxHeight: 420)
        }
    }
}

private struct SuggestRowView: View {
    let model: SuggestViewModel
    @Binding var row: SuggestViewModel.Row
    @FocusState private var emojiFocused: Bool

    var body: some View {
        let hint = model.nameHint(for: row)
        HStack(alignment: .top, spacing: 12) {
            Toggle("Add this category", isOn: $row.isOn).labelsHidden().toggleStyle(.checkbox).padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Icon", text: $row.emoji)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .help("Icon")
                        .focused($emojiFocused)
                        .onSubmit { model.commitEmoji(of: row.id) }
                        .onChange(of: emojiFocused) { if !emojiFocused { model.commitEmoji(of: row.id) } }
                    TextField("Name", text: $row.name)
                    Text(row.ids.count == 1 ? "1 photo" : "\(row.ids.count.formatted()) photos")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                if let hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.red)
                }
                HStack(spacing: 6) {
                    ForEach(row.ids.prefix(SuggestViewModel.thumbnailsPerRow), id: \.self) { id in
                        SuggestThumbnail(model: model, id: id)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .opacity(row.isOn ? 1 : 0.55)
    }
}

private struct SuggestThumbnail: View {
    let model: SuggestViewModel
    let id: MediaID
    @State private var image: CGImage?

    var body: some View {
        Rectangle().fill(.quaternary)
            .frame(width: 96, height: 72)
            .overlay {
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: id) { image = await model.thumbnail(id, maxPixel: 192) }
    }
}

#if DEBUG
@MainActor
private enum SuggestPreviewData {
    static func model() -> SuggestViewModel {
        let model = SuggestViewModel(review: ReviewPreviewData.review(), thumbnail: { _, _ in nil })
        let groups = [("Beach days", "🏖️", 12), ("Pets", "🐶", 9), ("Receipts", "🧾", 7)]
        model.rows = groups.map { name, emoji, n in
            SuggestViewModel.Row(CategorySuggestion(
                name: name, emoji: emoji, prompts: [], ids: (0..<n).map { "\(name)\($0).jpg" }))
        }
        return model
    }
}

#Preview("Suggest Categories") {
    SuggestSheet(model: SuggestPreviewData.model())
}
#endif
