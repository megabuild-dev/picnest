import PicnestCore
import SwiftUI

/// The sheet that adds photos to a category or a collection: a search field, a grid of the photos that are not in
/// the target yet, and **Add N Photos**. A category gets manual picks, so no file moves before **Done**.
struct AddPhotosSheet: View {
    let model: ReviewViewModel
    let target: AddPhotosTarget

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    /// The photos of the grid. Made again when the search text changes, not on each tap.
    @State private var candidates: [MediaID] = []
    @State private var picked: Set<MediaID> = []

    private static let tileWidth: Double = 120

    var body: some View {
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
                Button(CountText.addPhotos(picked.count)) { model.addPhotos(picked, to: target) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640, height: 520)
        .background(Theme.surface.color)
        .onAppear { candidates = model.addPhotosCandidates(for: target, matching: search) }
        .onChange(of: search) { candidates = model.addPhotosCandidates(for: target, matching: search) }
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
                if isPicked { SelectionCheck(diameter: 20).padding(6) }
            }
            .onTapGesture {
                if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
            }
            .accessibilityLabel(Text(verbatim: model.tile(id).name))
            .accessibilityAddTraits(isPicked ? [.isImage, .isSelected] : .isImage)
    }
}
