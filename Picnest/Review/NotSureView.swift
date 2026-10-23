import PicnestCore
import SwiftUI

/// The Not sure view (spec 3.4): an amber notice, then the photos in groups by best guess, largest group
/// first. Each group has **Select All** and **Accept N**. The toolbar has **Accept All Best Guesses**.
struct NotSureView: View {
    static let notice = "The app is not confident about these photos. They are grouped by best guess. "
        + "Accept a group, or select photos and move them."

    let model: ReviewViewModel

    var body: some View {
        let groups = model.notSureGroups
        let selection = model.selection
        PhotoGridInteractions(model: model) { onTap in
            if groups.isEmpty {
                ContentUnavailableView("Nothing left to check.", systemImage: "checkmark.circle",
                                       description: Text("All photos have a category."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Label(Self.notice, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .labelStyle(NoticeLabelStyle())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ReviewStyle.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 6)
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            Section {
                                LazyVGrid(columns: model.gridColumns, spacing: ReviewStyle.gridSpacing) {
                                    ForEach(group.ids, id: \.self) { id in
                                        SelectableTile(model: model, id: id, isSelected: selection.contains(id), onTap: onTap)
                                    }
                                }
                            } header: {
                                GroupHeader(group: group, index: index, model: model)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct NoticeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(ReviewStyle.amber)
            configuration.title
        }
    }
}

/// "Best guess: <category>", the count, **Select All** and **Accept N**.
private struct GroupHeader: View {
    let group: ReviewViewModel.NotSureGroup
    let index: Int
    let model: ReviewViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("Best guess: \(group.categoryName)").font(.system(size: 15, weight: .bold))
            Text(group.ids.count == 1 ? "1 photo" : "\(group.ids.count.formatted()) photos")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Select All") { model.selectGroup(at: index) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            Button("Accept \(group.ids.count.formatted())", systemImage: "checkmark") { model.acceptGroup(at: index) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.accentColor)
                .labelStyle(.titleAndIcon)
        }
        .padding(.top, index == 0 ? 12 : 18)
        .padding(.bottom, 10)
        // An opaque header, so tiles that scroll under it do not show through.
        .background(.background)
    }
}
