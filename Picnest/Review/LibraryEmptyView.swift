import SwiftUI

/// The message of an empty flat grid or list, with one action (the ViewModel decides which).
struct LibraryEmptyView: View {
    let model: ReviewViewModel

    var body: some View {
        switch model.emptyState {
        case .noResults:
            VStack(spacing: 12) {
                ContentUnavailableView.search(text: model.searchText)
                Button("Clear Search") { model.searchText = "" }
            }
        case .emptyFolder:
            VStack(spacing: 12) {
                ContentUnavailableView("No photos in this folder.", systemImage: "photo.on.rectangle")
                Button("Rescan", action: model.rescan).disabled(!model.canSortOrRescan)
            }
        case .nothingToReview:
            ContentUnavailableView("No photos need review.", systemImage: "checkmark.circle")
        case .noneChosen:
            ContentUnavailableView("You have not chosen a category for any photo yet.", systemImage: "photo.on.rectangle")
        case .findingSimilar, .similarSearchFailed:
            EmptyView()  // Only the Needs Review view has these.
        case nil:
            ContentUnavailableView("No Photos", systemImage: "photo.on.rectangle",
                                   description: Text("No photos are in this list."))
        }
    }
}
