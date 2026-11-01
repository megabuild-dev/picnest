import SwiftUI

/// The top of Needs Review: the title with its count, the amber notice, and the row of issue filters,
/// thumbnail size and sort menu.
struct NeedsReviewHeader: View {
    let model: ReviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Needs Review")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("\(model.count(of: .notSure)) photos need a quick check")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary.color)
            }
            if !model.isNoticeDismissed {
                NeedsReviewNotice { model.isNoticeDismissed = true }
            }
            HStack(spacing: 10) {
                ForEach(ReviewIssue.allCases, id: \.self) { issue in
                    if model.isReviewIssueAvailable(issue) { IssueMenu(model: model, issue: issue) }
                }
                Spacer(minLength: 12)
                if model.showsThumbnailSlider(layout: .grid) { SizeSlider(model: model) }
                ReviewSortMenu(model: model)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// The amber notice with a close button.
private struct NeedsReviewNotice: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.needsReview.color)
            Text("These photos are harder to categorize. Take a quick look and confirm or choose a better category.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary.color)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.needsReview.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

extension ReviewIssue {
    var title: LocalizedStringKey {
        switch self {
        case .lowConfidence: "Low confidence"
        case .noCategory: "No category"
        case .similarPhotos: "Similar photos"
        }
    }
}

/// A menu pill for 1 issue. Its menu turns the filter on, or shows all photos again.
private struct IssueMenu: View {
    let model: ReviewViewModel
    let issue: ReviewIssue

    var body: some View {
        let isOn = model.reviewIssue == issue
        Menu {
            Toggle(isOn: Binding(get: { isOn }, set: { model.reviewIssue = $0 ? issue : nil })) { Text(issue.title) }
            if model.reviewIssue != nil {
                Button("Show All") { model.reviewIssue = nil }
            }
        } label: {
            Text(issue.title)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .tint(isOn ? Theme.accent.color : nil)
        .fixedSize()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "Sort: Suggested". The suggested order is the lowest confidence first.
private struct ReviewSortMenu: View {
    let model: ReviewViewModel

    var body: some View {
        Menu {
            Picker("Sort Order", selection: Bindable(model).sortOrder) {
                ForEach(ReviewViewModel.SortOrder.allCases) { Text($0.reviewTitle).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text("Sort: \(model.sortOrder.reviewTitle)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort order")
    }
}

extension ReviewViewModel.SortOrder {
    /// The name in the Needs Review sort menu. The lowest confidence first is the suggested order.
    var reviewTitle: String {
        switch self {
        case .lowestConfidence: String(localized: "Suggested")
        case .date: String(localized: "Date")
        case .name: String(localized: "Name")
        }
    }
}
