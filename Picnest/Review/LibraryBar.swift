import SwiftUI

/// The row under the toolbar (spec 4.3): the filter chips, the thumbnail size slider and the sort menu.
/// The chips show for All Photos and Chosen by you only. Needs Review has its own header and filter menus.
struct LibraryBar: View {
    let model: ReviewViewModel
    let layout: LibraryLayout

    var body: some View {
        HStack(spacing: 8) {
            if model.showsFilterChips {
                HStack(spacing: 8) {
                    ForEach(PhotoFilter.allCases, id: \.self) { filter in
                        FilterChip(title: filter.title, isSelected: model.filter == filter) { model.filter = filter }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Filter")
            }
            Spacer(minLength: 12)
            if model.showsThumbnailSlider(layout: layout) { SizeSlider(model: model) }
            // A category has the sort menu in its header.
            if !model.showsCategoryHeader {
                Picker("Sort Order", selection: Bindable(model).sortOrder) {
                    ForEach(ReviewViewModel.SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Sort order")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

extension PhotoFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .needsReview: "Needs review"
        case .chosenByYou: "Chosen by you"
        }
    }
}

/// A pill: filled with the accent when selected, neutral otherwise.
private struct FilterChip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.onAccent.color : Theme.textPrimary.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(isSelected ? Theme.accent.color : Theme.textPrimary.color.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Thumbnail size: left is small (80 pt), right is large (240 pt).
struct SizeSlider: View {
    let model: ReviewViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3").font(.system(size: 10)).foregroundStyle(Theme.textSecondary.color)
            Slider(value: Bindable(model).thumbnailSize, in: ReviewViewModel.thumbnailSizeRange)
                .frame(width: 90)
                .controlSize(.small)
            Image(systemName: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
        }
        .help("Thumbnail size")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thumbnail size")
    }
}

/// The footer under the photos: "N photos · Stored on this Mac".
struct LibraryFooter: View {
    let count: Int

    var body: some View {
        (Text(CountText.photos(count)) + Text(verbatim: " · ") + Text("Stored on this Mac"))
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}
