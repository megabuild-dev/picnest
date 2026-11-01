import PicnestCore
import SwiftUI

/// The sheet that names a new collection, or renames one. The view model owns the rules (`saveCollection`).
struct CollectionNameSheet: View {
    let model: ReviewViewModel
    let editor: CollectionEditor

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    /// True after the user typed or tried to save, so an empty new name shows no error at first.
    @State private var touched = false
    @FocusState private var nameFocused: Bool

    init(model: ReviewViewModel, editor: CollectionEditor) {
        self.model = model
        self.editor = editor
        _name = State(initialValue: model.collectionSheetName)
    }

    private var issue: CollectionNameIssue? {
        model.validateCollectionName(name, excluding: model.collectionSheetExcluding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            title
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary.color)
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .onChange(of: name) { touched = true }
                if touched, let issue {
                    Text(issue.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.destructive.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(issue != nil)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.surface.color)
        .onAppear { nameFocused = true }
    }

    private var title: Text {
        switch editor {
        case .new: Text("New Collection")
        case .rename: Text("Rename Collection")
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch editor {
        case .new: "Create"
        case .rename: "Save"
        }
    }

    private func save() {
        touched = true
        model.saveCollection(name: name)
    }
}

extension CollectionNameIssue {
    /// The text under the name field of the collection sheet.
    var message: LocalizedStringKey {
        switch self {
        case .empty: "Enter a name."
        case .duplicate: "A collection with this name already exists."
        }
    }
}
