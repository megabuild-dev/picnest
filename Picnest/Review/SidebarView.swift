import PicnestCore
import SwiftUI

/// Review sidebar (spec 3.3): sections Review, Categories, Tools and Other, each item with a count.
/// Category rows take dropped photos, drag to change the order, and have a context menu: Rename,
/// Change Icon, Merge Into…, Delete.
struct SidebarView: View {
    let model: ReviewViewModel

    @State private var dropTarget: CategoryID?
    @State private var renaming: CategoryID?
    @State private var nameDraft = ""
    @State private var editingIcon: CategoryID?
    @State private var deleting: CategoryID?

    private var selection: Binding<ReviewViewModel.SidebarItem?> {
        Binding(get: { model.selectedItem }, set: { if let item = $0 { model.selectedItem = item } })
    }

    var body: some View {
        let counts = model.sidebarCounts
        return List(selection: selection) {
            Section("Review") {
                row(counts, .all, "All photos", icon: .symbol("photo.on.rectangle", .secondary))
                row(counts, .notSure, "Not sure", icon: .symbol("exclamationmark.triangle.fill", ReviewStyle.amber))
                row(counts, .changedByYou, "Changed by you", icon: .symbol("checkmark", ReviewStyle.green))
            }
            Section("Categories") {
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
                .foregroundStyle(.secondary)
                .selectionDisabled()
            }
            Section("Tools") {
                row(counts, .duplicates, "Duplicates", icon: .symbol("square.on.square", .secondary))
            }
            Section("Other") {
                row(counts, .dontMove, "Don't move", icon: .symbol("nosign", .secondary))
                row(counts, .videos, "Videos", icon: .symbol("video", .secondary))
                row(counts, .unreadable, "Unreadable", icon: .symbol("exclamationmark.octagon", .secondary))
            }
        }
        .listStyle(.sidebar)
        .alert("Rename Category", isPresented: isPresented($renaming)) {
            TextField("Name", text: $nameDraft)
            Button("Rename") { if let renaming { model.renameCategory(renaming, to: nameDraft) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deletingTitle, isPresented: isPresented($deleting), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let deleting { model.deleteCategory(deleting) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deletingTitle: String { deleting.map(model.deleteConfirmation(for:)) ?? "" }

    private func categoryRow(_ counts: [ReviewViewModel.SidebarItem: Int], _ category: PicnestCore.Category) -> some View {
        let id = category.id
        return row(counts, .category(id), category.displayName, icon: .emoji(category.emoji))
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
                Button("Rename…") {
                    nameDraft = category.displayName
                    renaming = id
                }
                Button("Change Icon…") { editingIcon = id }
                Menu("Merge Into…") {
                    ForEach(model.mergeTargets(for: id)) { target in
                        Button("\(target.emoji) \(target.displayName)") { model.merge(id, into: target.id) }
                    }
                }
                .disabled(model.mergeTargets(for: id).isEmpty)
                Divider()
                Button("Reveal in Finder") { model.showCategoryInFinder(id) }
                    .disabled(model.categoryFolder(id) == nil)
                Divider()
                Button("Delete…", role: .destructive) { deleting = id }
                    .disabled(!model.canDeleteCategory)
            }
            .popover(isPresented: Binding(
                get: { editingIcon == id }, set: { if !$0, editingIcon == id { editingIcon = nil } }
            ), arrowEdge: .trailing) {
                EmojiField(current: category.emoji) { emoji in
                    if model.setEmoji(id, emoji) { editingIcon = nil }
                }
            }
    }

    private func row(_ counts: [ReviewViewModel.SidebarItem: Int], _ item: ReviewViewModel.SidebarItem, _ title: String, icon: SidebarIcon) -> some View {
        Label {
            Text(title).lineLimit(1)
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

/// The Change Icon popover: a field for 1 emoji. Input that is not exactly 1 emoji is ignored.
private struct EmojiField: View {
    let current: String
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type or paste 1 emoji").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                TextField(current, text: $text)
                    .font(.system(size: 22))
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .focused($isFocused)
                    .onSubmit { onSubmit(text) }
                Button("Set") { onSubmit(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ReviewViewModel.isSingleEmoji(text.trimmingCharacters(in: .whitespaces)))
            }
        }
        .padding(12)
        .onAppear { isFocused = true }
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
