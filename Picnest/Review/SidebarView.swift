import PicnestCore
import SwiftUI

/// Review sidebar (spec 4.2): sections Library, Categories and Tools, each item with a count.
/// Category rows take dropped photos, drag to change the order, and have a context menu: Rename,
/// Change Icon, Merge Into…, Delete.
struct SidebarView: View {
    let model: ReviewViewModel

    @State private var dropTarget: CategoryID?

    private var selection: Binding<ReviewViewModel.SidebarItem?> {
        Binding(get: { model.selectedItem }, set: { if let item = $0 { model.selectedItem = item } })
    }

    var body: some View {
        let counts = model.sidebarCounts
        return List(selection: selection) {
            Section {
                row(counts, .all, "All Photos", icon: .symbol("photo.on.rectangle", Theme.textSecondary.color))
                row(counts, .notSure, "Needs Review", icon: .symbol("exclamationmark.triangle.fill", Theme.needsReview.color))
            } header: { sectionHeader("Library") }
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
        }
        .listStyle(.sidebar)
        .tint(Theme.accent.color)
        .confirmationDialog(deletingTitle, isPresented: isPresented(Bindable(model).deletingCategory), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting = model.deletingCategory { Task { await model.deleteCategory(deleting) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.deletingCategory.map(model.deleteMessage(for:)) ?? "")
        }
    }

    /// A section title as in the mockups: regular weight, secondary color, no capitals.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
    }

    private var deletingTitle: String { model.deletingCategory.map(model.deleteConfirmation(for:)) ?? "" }

    private func categoryRow(_ counts: [ReviewViewModel.SidebarItem: Int], _ category: PicnestCore.Category) -> some View {
        let id = category.id
        return row(counts, .category(id), Text(verbatim: category.displayName), icon: .emoji(category.emoji))
            .background {
                if dropTarget == id {
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.22))
                        .padding(-4)
                }
            }
            .dropDestination(for: MediaIDs.self) { items, _ in
                model.drop(items.flatMap(\.ids), on: id)
            } isTargeted: { targeted in
                if targeted { dropTarget = id } else if dropTarget == id { dropTarget = nil }
            }
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

    /// A Bool binding that is true while `value` is set. Setting it to false clears `value`.
    private func isPresented<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
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
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }
}
