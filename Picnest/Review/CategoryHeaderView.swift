import PicnestCore
import SwiftUI

/// The top of a category screen: the icon tile, the name with its photo count, and the Rename button,
/// sort menu and more menu. The actions are the ones of the sidebar context menu.
struct CategoryHeaderView: View {
    let model: ReviewViewModel
    let category: PicnestCore.Category
    let photoCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(verbatim: category.emoji)
                .font(.system(size: 30))
                .frame(width: 56, height: 56)
                .background(Theme.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: category.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.color)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text("\(photoCount) photos")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary.color)
            }
            Spacer(minLength: 12)
            Button("Rename") { model.editingCategory = category.id }
                .buttonStyle(.bordered)
            sortMenu
            moreMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
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
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Change Icon…") { model.editingCategory = category.id }
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
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}
