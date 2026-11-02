import SwiftUI

/// The bottom strip: the photos of the set, and the step buttons with "1 of 5".
struct EditorFilmstrip: View {
    @Bindable var model: PhotoEditorViewModel
    let library: ReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: model.setCountText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.allPhotos) { photo in
                            Button { model.select(photo.id) } label: { thumbnail(photo) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: photo.fileName))
                                .accessibilityAddTraits(photo.id == model.current.id ? .isSelected : [])
                        }
                    }
                    .padding(2)
                }
                step("chevron.left", label: "Previous photo", offset: -1, enabled: model.canStepBack)
                Text(verbatim: model.positionText).font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary.color)
                step("chevron.right", label: "Next photo", offset: 1, enabled: model.canStepForward)
            }
            .frame(height: Theme.Metrics.filmstripHeight)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.background.color)
    }

    private func thumbnail(_ photo: EditorPhoto) -> some View {
        let selected = photo.id == model.current.id
        return ThumbnailImage(model: library, id: photo.id, width: 140)
            .frame(width: 140, height: Theme.Metrics.filmstripHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent.color : .clear, lineWidth: 3))
    }

    private func step(_ symbol: String, label: LocalizedStringKey, offset: Int, enabled: Bool) -> some View {
        Button { model.step(by: offset) } label: { Image(systemName: symbol) }
            .buttonStyle(.bordered)
            .disabled(!enabled)
            .accessibilityLabel(Text(label))
    }
}
