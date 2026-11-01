import SwiftUI

/// A rounded card on the surface color. The sections of the Sort sheet use it.
struct SortCard<Content: View>: View {
    var stroke: Color = Theme.textSecondary.color.opacity(0.2)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.color, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 1) }
    }
}

/// A radio choice as a card: a soft accent fill and ring when selected.
struct ChoiceCard: View {
    let title: Text
    let detail: Text
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Theme.accent.color : Theme.textSecondary.color)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title.fontWeight(.semibold).foregroundStyle(Theme.textPrimary.color)
                    detail.font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isOn ? Theme.selection.color : Theme.surface.color, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isOn ? Theme.accent.color : Theme.textSecondary.color.opacity(0.2),
                                  lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The folder tree preview. The first line is the destination. It scrolls in both directions.
struct PreviewTree: View {
    let lines: [String]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).fixedSize()
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.textPrimary.color)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 60, maxHeight: 150)
        .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview"))
        .accessibilityValue(Text(verbatim: lines.joined(separator: ", ")))
    }
}
