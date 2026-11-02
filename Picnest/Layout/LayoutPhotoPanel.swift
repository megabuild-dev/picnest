import PicnestCore
import SwiftUI

/// The left panel: search, the source of the photos, and the photos to drag onto the page.
struct LayoutPhotoPanel: View {
    @Bindable var model: LayoutEditorViewModel
    let library: ReviewViewModel
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos").font(.system(size: 15, weight: .semibold))
            search
            Picker("Photos", selection: Binding(get: { model.sourceID }, set: model.setSource)) {
                ForEach(model.sourceOptions) { Text(verbatim: $0.title).tag($0.id) }
            }
            .labelsHidden().pickerStyle(.menu)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.sourcePhotos) { tile($0) }
                }
            }
            HStack {
                Text(verbatim: model.sourceCountText)
                Spacer(minLength: 8)
                Text("Drag to add to layout")
            }
            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
        }
        .padding(16)
        .frame(width: Theme.Metrics.layoutPhotoPanel)
        .background(Theme.sidebar.color)
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary.color).accessibilityHidden(true)
            TextField("Search photos", text: $model.searchText).textFieldStyle(.plain)
        }
        .padding(8)
        .background(Theme.placeholderFill.color, in: RoundedRectangle(cornerRadius: 8))
    }

    private func tile(_ photo: LayoutPhoto) -> some View {
        let used = model.usedIDs.contains(photo.id)
        return ThumbnailImage(model: library, id: photo.id, width: 100)
            .frame(height: 110).frame(maxWidth: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.tileCorner))
            .overlay(alignment: .topTrailing) {
                if used {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.onAccent.color, Theme.accent.color)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.add([photo.id]) }
            .draggable(MediaIDs(ids: [photo.id]))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: photo.fileName))
            .accessibilityValue(used ? Text("In Layout") : Text(verbatim: ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Add to Layout")) { model.add([photo.id]) }
    }
}
