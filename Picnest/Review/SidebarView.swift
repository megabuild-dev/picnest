import PicnestCore
import SwiftUI

/// Review sidebar (spec 4.2): sections Library, Collections, Categories, Tools and Recently Deleted, each item with a count.
/// Category rows take dropped photos, drag to change the order, and have a context menu: Rename,
/// Change Icon, Merge Into…, Delete.
struct SidebarView: View {
    let model: ReviewViewModel
    /// The appearance and language bar at the bottom. Nil in previews.
    var preferences: SidebarPreferences?

    @State private var dropTarget: UUID?

    private var selection: Binding<ReviewViewModel.SidebarItem?> {
        Binding(get: { model.selectedItem }, set: { if let item = $0 { model.selectedItem = item } })
    }

    var body: some View {
        let counts = model.sidebarCounts
        return List(selection: selection) {
            Section {
                row(counts, .all, "All Photos", icon: .symbol("photo.on.rectangle", Theme.textSecondary.color))
                row(counts, .notSure, "Needs Review", icon: .symbol("exclamationmark.triangle.fill", Theme.needsReview.color))
                row(counts, .favorites, "Favorites", icon: .symbol("heart", Theme.textSecondary.color))
            } header: { sectionHeader("Library") }
            Section {
                ForEach(model.collections) { collection in
                    collectionRow(counts, collection)
                }
            } header: { collectionsHeader }
            Section {
                ForEach(model.categories) { category in
                    categoryRow(counts, category)
                }
                .onMove(perform: model.moveCategories)
                Button {
                    model.requestNewCategory(movingSelection: false)
                } label: {
                    Label("New Category…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary.color)
                .selectionDisabled()
            } header: { sectionHeader("Categories") }
            Section {
                row(counts, .duplicates, "Duplicates", icon: .symbol("square.on.square", Theme.textSecondary.color))
                row(counts, .dontMove, "Don't move", icon: .symbol("nosign", Theme.textSecondary.color))
                row(counts, .videos, "Videos", icon: .symbol("video", Theme.textSecondary.color))
                row(counts, .unreadable, "Unreadable", icon: .symbol("exclamationmark.octagon", Theme.textSecondary.color))
            } header: { sectionHeader("Tools") }
            Section {
                row(counts, .recentlyDeleted, "Recently Deleted", icon: .symbol("trash", Theme.textSecondary.color))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar.color)
        .tint(Theme.accent.color)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let preferences {
                SidebarPreferencesBar(appearance: preferences.appearance, language: preferences.language,
                                      relauncher: preferences.relauncher)
            }
        }
    }

    /// A section title as in the mockups: regular weight, secondary color, no capitals.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
    }

    /// The title of the Collections section, with the button that makes a collection.
    private var collectionsHeader: some View {
        HStack {
            sectionHeader("Collections")
            Spacer(minLength: 0)
            Button {
                model.requestNewCollection(adding: [])
            } label: {
                Label("New Collection", systemImage: "plus").labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary.color)
            .help("New Collection")
        }
    }

    private func collectionRow(_ counts: [ReviewViewModel.SidebarItem: Int], _ collection: PhotoCollection) -> some View {
        let id = collection.id
        return row(counts, .collection(id), Text(verbatim: collection.name),
                   icon: .symbol("square.stack", Theme.textSecondary.color))
            .sidebarDropTarget(id, current: $dropTarget) { model.dropOnCollection($0, id) }
            .contextMenu {
                Button("Rename…") { model.requestRenameCollection(id) }
                CreateLayoutButton(model: model, origin: .collection(id))
                Divider()
                Button("Delete…", role: .destructive) { model.deletingCollection = id }
            }
    }

    private func categoryRow(_ counts: [ReviewViewModel.SidebarItem: Int], _ category: PicnestCore.Category) -> some View {
        let id = category.id
        return row(counts, .category(id), Text(verbatim: category.displayName), icon: .emoji(category.emoji))
            .sidebarDropTarget(id, current: $dropTarget) { model.drop($0, on: id) }
            .contextMenu {
                Button("Rename…") { model.editingCategory = id }
                Button("Change Icon…") { model.editingCategory = id }
                Menu("Merge Into…") {
                    ForEach(model.mergeTargets(for: id)) { target in
                        Button { model.merge(id, into: target.id) } label: {
                            Text(verbatim: "\(target.emoji) \(target.displayName)")
                        }
                    }
                }
                .disabled(model.mergeTargets(for: id).isEmpty)
                CreateLayoutButton(model: model, origin: .category(id))
                Divider()
                Button("Reveal in Finder") { model.showCategoryInFinder(id) }
                    .disabled(model.categoryFolder(id) == nil)
                Divider()
                Button("Delete…", role: .destructive) { model.deletingCategory = id }
                    .disabled(!model.canDeleteCategory)
            }
    }

    private func row(_ counts: [ReviewViewModel.SidebarItem: Int], _ item: ReviewViewModel.SidebarItem, _ title: LocalizedStringKey, icon: SidebarIcon) -> some View {
        row(counts, item, Text(title), icon: icon)
    }

    /// A row whose title is already a `Text`: a category name is data and stays as the user typed it.
    private func row(_ counts: [ReviewViewModel.SidebarItem: Int], _ item: ReviewViewModel.SidebarItem, _ title: Text, icon: SidebarIcon) -> some View {
        Label {
            title.lineLimit(1)
        } icon: {
            icon
        }
        .badge(Text((counts[item] ?? 0).formatted()))
        .tag(item)
    }
}

private extension View {
    /// A sidebar row that takes dropped photos. It shows the accent highlight while a drag is over it.
    /// `current` is the id of the row that is under the drag, shared by all rows.
    func sidebarDropTarget(_ id: UUID, current: Binding<UUID?>, perform: @escaping ([MediaID]) -> Bool) -> some View {
        background {
            if current.wrappedValue == id {
                RoundedRectangle(cornerRadius: 6).fill(Theme.accent.color.opacity(0.22))
                    .padding(-4)
            }
        }
        .dropDestination(for: MediaIDs.self) { items, _ in
            perform(items.flatMap(\.ids))
        } isTargeted: { targeted in
            if targeted { current.wrappedValue = id } else if current.wrappedValue == id { current.wrappedValue = nil }
        }
    }
}

/// An SF Symbol or a category emoji in a small rounded square (spec 6.1).
private struct SidebarIcon: View {
    enum Content {
        case symbol(String, Color)
        case emoji(String)
    }

    let content: Content

    static func symbol(_ name: String, _ tint: Color) -> SidebarIcon { SidebarIcon(content: .symbol(name, tint)) }
    static func emoji(_ emoji: String) -> SidebarIcon { SidebarIcon(content: .emoji(emoji)) }

    var body: some View {
        Group {
            switch content {
            case .symbol(let name, let tint):
                Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            case .emoji(let emoji):
                Text(emoji).font(.system(size: 12))
            }
        }
        .frame(width: 22, height: 22)
        .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.textPrimary.color.opacity(0.08), lineWidth: 0.5))
    }
}
