import SwiftUI

/// "Best guess: <category>", the count, **Select All** and **Accept N** of a group in Needs Review.
/// N is the number of photos that show in the group.
struct NotSureGroupHeader: View {
    let group: ReviewViewModel.NotSureGroup
    let index: Int
    let model: ReviewViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("Best guess: \(group.categoryName)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary.color)
            Text(CountText.photos(group.ids.count))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary.color)
            Spacer()
            Button("Select All") { model.selectGroup(at: index) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            Button("Accept \(group.ids.count.formatted())", systemImage: "checkmark") { model.acceptGroup(at: index) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent.color)
                .labelStyle(.titleAndIcon)
        }
        .padding(.top, index == 0 ? 8 : 18)
        .padding(.bottom, 10)
        // An opaque header, so tiles that scroll under it do not show through.
        .background(.background)
    }
}
