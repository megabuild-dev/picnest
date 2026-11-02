import SwiftUI

extension EditorTool {
    var title: LocalizedStringKey {
        switch self {
        case .crop: "Crop"
        case .straighten: "Straighten"
        case .rotate: "Rotate"
        case .adjust: "Adjust"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .crop: "Trim and reframe"
        case .straighten: "Fix horizon"
        case .rotate: "Turn photo"
        case .adjust: "Tone and color"
        }
    }

    var symbol: String {
        switch self {
        case .crop: "crop"
        case .straighten: "angle"
        case .rotate: "rotate.right"
        case .adjust: "slider.horizontal.3"
        }
    }
}

/// The left rail: the 4 tools. A tool sets the canvas mode, and the panel scrolls to its section.
struct EditorToolRail: View {
    @Bindable var model: PhotoEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                Button { model.tool = tool } label: { row(tool) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tool.title))
                    .accessibilityHint(Text(tool.subtitle))
                    .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: Theme.Metrics.editorToolRail)
        .background(Theme.sidebar.color)
    }

    private func row(_ tool: EditorTool) -> some View {
        let selected = model.tool == tool
        return HStack(spacing: 12) {
            Image(systemName: tool.symbol).font(.system(size: 20))
                .foregroundStyle(selected ? Theme.accent.color : Theme.textPrimary.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(.system(size: 14, weight: .semibold))
                Text(tool.subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary.color)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? Theme.selection.color : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if selected { Capsule().fill(Theme.accent.color).frame(width: 3).padding(.vertical, 6) }
        }
        .contentShape(Rectangle())
    }
}
