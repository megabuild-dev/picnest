import PicnestCore
import SwiftUI

/// The sheet that adds photos to a category or a collection: a search field, a grid of the photos that are not in
/// the target yet, and **Add N Photos**. A category gets manual picks, so no file moves before **Done**.
struct AddPhotosSheet: View {
    let model: ReviewViewModel
    let target: AddPhotosTarget

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var picked: Set<MediaID> = []

    private static let tileWidth: Double = 120

    var body: some View {
        let candidates = model.addPhotosCandidates(for: target, matching: search)
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Photos")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: 8)], spacing: 8) {
                    ForEach(candidates, id: \.self) { id in tile(id) }
                }
            }
            .frame(maxHeight: .infinity)
            .overlay {
                if candidates.isEmpty { Text("No Photos").foregroundStyle(Theme.textSecondary.color) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(CountText.addPhotos(picked.count)) { model.addPhotos(orderedPicks(in: candidates), to: target) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640, height: 520)
        .background(Theme.surface.color)
    }

    private func tile(_ id: MediaID) -> some View {
        let isPicked = picked.contains(id)
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner)
        return Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { ThumbnailImage(model: model, id: id, width: Self.tileWidth) }
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                shape.strokeBorder(isPicked ? Theme.accent.color : Theme.textPrimary.color.opacity(0.1),
                                   lineWidth: isPicked ? 3 : 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if isPicked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.onAccent.color)
                        .frame(width: 20, height: 20)
                        .background(Theme.accent.color, in: Circle())
                        .padding(6)
                }
            }
            .onTapGesture {
                if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
            }
            .accessibilityLabel(Text(verbatim: model.tile(id).name))
            .accessibilityAddTraits(isPicked ? [.isImage, .isSelected] : .isImage)
    }

    /// The picks in the order of the grid. Picks that a search hides still count.
    private func orderedPicks(in shown: [MediaID]) -> [MediaID] {
        let shownPicks = shown.filter(picked.contains)
        return shownPicks + picked.subtracting(shownPicks).sorted()
    }
}
