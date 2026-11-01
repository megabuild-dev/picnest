import PicnestCore
import SwiftUI

/// The Needs Review view (spec 4.3): a title, a closable amber notice, the issue filters and the sort menu,
/// then the photos in groups by best guess, largest group first. Each group has **Select All** and
/// **Accept N**. The toolbar has **Accept All Best Guesses**.
struct NotSureView: View {
    let model: ReviewViewModel

    var body: some View {
        let groups = model.notSureGroups
        let selection = model.selection
        PhotoGridInteractions(model: model, selectionBar: .needsReview) { onTap in
            VStack(spacing: 0) {
                NeedsReviewHeader(model: model)
                if let state = model.emptyState {
                    NeedsReviewEmptyView(model: model, state: state)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                Section {
                                    LazyVGrid(columns: model.gridColumns, spacing: Theme.Metrics.gridSpacing) {
                                        ForEach(group.ids, id: \.self) { id in
                                            SelectableTile(model: model, id: id, isSelected: selection.contains(id), onTap: onTap)
                                        }
                                    }
                                } header: {
                                    NotSureGroupHeader(group: group, index: index, model: model)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }
}

/// What Needs Review shows when it has no photo to show: nothing left, or no match for the search or filter.
private struct NeedsReviewEmptyView: View {
    let model: ReviewViewModel
    let state: ReviewViewModel.EmptyState

    var body: some View {
        VStack(spacing: 12) {
            switch state {
            case .noResults:
                if model.reviewIssue != nil && Self.isBlank(model.searchText) {
                    ContentUnavailableView("No photos match this filter.", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
                Button("Clear Filters", action: model.clearReviewFilters)
            case .findingSimilar:
                ProgressView().controlSize(.small)
                Text("Looking for similar photos…").foregroundStyle(Theme.textSecondary.color)
            case .similarSearchFailed(let message):
                ContentUnavailableView("Could not look for similar photos.", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                Button("Clear Filters", action: model.clearReviewFilters)
            default:
                ContentUnavailableView("Nothing left to check.", systemImage: "checkmark.circle",
                                       description: Text("All photos have a category."))
            }
        }
        // A search that was cancelled starts again when the view shows.
        .task(id: state) { if state == .findingSimilar { await model.duplicates.find() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
