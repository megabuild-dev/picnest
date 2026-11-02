import PicnestCore
import SwiftUI

/// The top of a category screen and of a collection screen: the icon tile, the name with its photo count, and
/// **Add Photos**, **Rename**, the sort menu and the more menu. The caller gives the icon, the actions, and the
/// items of the more menu.
struct PhotoSetHeaderView<MoreItems: View>: View {
    enum Icon {
        case emoji(String)
        case symbol(String)
    }

    let model: ReviewViewModel
    let icon: Icon
    let name: String
    let photoCount: Int
    let addPhotos: () -> Void
    let rename: () -> Void
    @ViewBuilder let moreItems: () -> MoreItems

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            iconTile
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.color)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(CountText.photos(photoCount))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary.color)
            }
            Spacer(minLength: 12)
            Button("Add Photos", systemImage: "plus", action: addPhotos)
                .buttonStyle(.bordered)
            Button("Rename", action: rename)
                .buttonStyle(.bordered)
            sortMenu
            moreMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var iconTile: some View {
        Group {
            switch icon {
            case .emoji(let emoji): Text(verbatim: emoji).font(.system(size: 30))
            case .symbol(let name): Image(systemName: name).font(.system(size: 24)).foregroundStyle(Theme.accent.color)
            }
        }
        .frame(width: 56, height: 56)
        .background(Theme.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }

    private var sortMenu: some View {
        Menu("Sort Order", systemImage: "arrow.up.arrow.down") {
            Picker("Sort Order", selection: Bindable(model).sortOrder) {
                ForEach(ReviewViewModel.SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort order")
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle", content: moreItems)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
    }
}

/// The items of the more menu of a category. They are the ones of the sidebar context menu.
struct CategoryMoreItems: View {
    let model: ReviewViewModel
    let category: PicnestCore.Category

    var body: some View {
        Button("Change Icon…") { model.editingCategory = category.id }
        CreateLayoutButton(model: model, origin: .category(category.id))
        Menu("Merge Into…") {
            ForEach(model.mergeTargets(for: category.id)) { target in
                Button { model.merge(category.id, into: target.id) } label: {
                    Text(verbatim: "\(target.emoji) \(target.displayName)")
                }
            }
        }
        .disabled(model.mergeTargets(for: category.id).isEmpty)
        Divider()
        Button("Reveal in Finder") { model.showCategoryInFinder(category.id) }
            .disabled(model.categoryFolder(category.id) == nil)
        Divider()
        Button("Delete…", role: .destructive) { model.deletingCategory = category.id }
            .disabled(!model.canDeleteCategory)
    }
}

/// The items of the more menu of a collection.
struct CollectionMoreItems: View {
    let model: ReviewViewModel
    let collection: PhotoCollection

    var body: some View {
        CreateLayoutButton(model: model, origin: .collection(collection.id))
        Divider()
        Button("Delete…", role: .destructive) { model.deletingCollection = collection.id }
    }
}
