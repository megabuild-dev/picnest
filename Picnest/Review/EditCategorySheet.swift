import PicnestCore
import SwiftUI

/// The Edit Category sheet: name, icon and folder. The folder always follows the category name (the
/// folder rename and the name change are one step in `ReviewService.rename`), so the folder row is read only.
struct EditCategorySheet: View {
    let model: ReviewViewModel
    let category: PicnestCore.Category
    let dismiss: () -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var customEmoji = ""
    @FocusState private var nameFocused: Bool

    /// The icons that the picker offers. The current icon replaces the first one when it is not in the list.
    private static let presets = ["📁", "🍜", "✈️", "🐾", "👨‍👩‍👧", "🧾", "🌅"]

    init(model: ReviewViewModel, category: PicnestCore.Category, dismiss: @escaping () -> Void) {
        self.model = model
        self.category = category
        self.dismiss = dismiss
        _name = State(initialValue: category.displayName)
        _emoji = State(initialValue: category.emoji)
    }

    private var issue: ReviewViewModel.CategoryNameIssue? { model.validateCategoryName(name, excluding: category.id) }

    private var icons: [String] {
        var list = Self.presets
        if !list.contains(emoji) { list[0] = emoji }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Category")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            field("Name") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(save)
                    if let issue {
                        Text(issue.message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.destructive.color)
                    }
                }
            }
            field("Icon") {
                HStack(spacing: 8) {
                    ForEach(icons, id: \.self) { icon in iconButton(icon) }
                    TextField("Emoji", text: $customEmoji)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .onChange(of: customEmoji) { _, value in
                            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            if ReviewViewModel.isSingleEmoji(value) { emoji = value }
                        }
                        .accessibilityLabel("Type or paste 1 emoji")
                }
            }
            field("Folder") {
                HStack {
                    Text(verbatim: model.categoryFolderName(category.id))
                        .foregroundStyle(Theme.textPrimary.color)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Reveal in Finder") { model.showCategoryInFinder(category.id) }
                        .disabled(model.categoryFolder(category.id) == nil)
                }
            }
            Text("The folder follows the category name.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary.color)
            createCollectionRow
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSaveCategoryEdit(category.id, name: name, emoji: emoji))
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.surface.color)
        .onAppear { nameFocused = true }
    }

    /// Makes a collection with the name of the category. The category does not change.
    private var createCollectionRow: some View {
        Button { model.createCollectionInstead(of: category.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.stack").foregroundStyle(Theme.accent.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a collection instead").font(.system(size: 13, weight: .semibold))
                    Text("Group photos without moving files.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary.color)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary.color)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.textPrimary.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary.color)
    }

    private func save() {
        if model.saveCategoryEdit(category.id, name: name, emoji: emoji) { dismiss() }
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary.color)
            content()
        }
        .accessibilityElement(children: .contain)
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = icon == emoji
        return Button { emoji = icon } label: {
            Text(verbatim: icon)
                .font(.system(size: 18))
                .frame(width: 34, height: 34)
                .background(isSelected ? Theme.accent.color.opacity(0.18) : Theme.textPrimary.color.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isSelected { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.color, lineWidth: 2) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: icon))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
