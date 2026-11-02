import PicnestCore
import SwiftUI

/// The right panel: kind, paper, orientation, presets, spacing, margin, background, captions, and export.
struct LayoutSettingsPanel: View {
    @Bindable var model: LayoutEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Layout") { kinds }
                section("Paper size") { paper }
                orientation
                section("Layout presets") { presets }
                Divider()
                section("Spacing") { inset("Spacing", value: Binding(get: { model.document.spacing }, set: model.setSpacing), text: model.spacingText) }
                section("Margin") { inset("Margin", value: Binding(get: { model.document.margin }, set: model.setMargin), text: model.marginText) }
                section("Background") { swatches }
                Divider()
                captions
                Divider()
                section("Export") { resolution }
            }
            .padding(20)
        }
        .frame(width: Theme.Metrics.editorPanel)
        .background(Theme.surface.color)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
    }

    // MARK: - Layout, paper, orientation

    private var kinds: some View {
        HStack(spacing: 8) {
            ForEach([LayoutKind.collage, .contactSheet], id: \.self) { kind in
                LayoutChoiceTile(selected: model.document.kind == kind, label: Text(verbatim: kind.title)) {
                    model.setKind(kind)
                } content: {
                    Image(systemName: kind == .collage ? "rectangle.split.2x2" : "square.grid.3x3").font(.system(size: 18))
                }
            }
        }
    }

    private var paper: some View {
        Menu {
            Picker("Paper size", selection: Binding(get: { model.document.paper }, set: model.setPaper)) {
                ForEach(PaperSize.allCases, id: \.self) {
                    Text(verbatim: LayoutEditorViewModel.paperText($0, orientation: model.document.orientation)).tag($0)
                }
            }
        } label: {
            Text(verbatim: model.paperText)
        }
        .accessibilityLabel(Text("Paper size"))
    }

    private var orientation: some View {
        Picker("Orientation", selection: Binding(get: { model.document.orientation }, set: model.setOrientation)) {
            ForEach(PageOrientation.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Presets

    private var presets: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            if model.document.kind == .contactSheet {
                ForEach(GridPreset.presets, id: \.self) { preset in
                    presetTile(preset.previewNode, title: preset.title, selected: model.document.grid == preset) { model.setGrid(preset) }
                }
            } else {
                ForEach(CollageTemplate.allCases, id: \.self) { template in
                    presetTile(template.root, title: template.title, selected: model.document.template == template) {
                        model.setTemplate(template)
                    }
                }
            }
        }
    }

    private func presetTile(_ node: SplitNode, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        LayoutChoiceTile(selected: selected, label: Text(verbatim: title), action: action) {
            PresetPreview(node: node).frame(height: 36)
        }
    }

    // MARK: - Spacing, margin, background

    private func inset(_ title: LocalizedStringKey, value: Binding<Double>, text: String) -> some View {
        EditorValueSlider(
            title: title, value: value, range: 0...LayoutDocument.maxInset, step: 1,
            showsLabel: false, text: text, onEditing: { if $0 { model.beginDrag() } else { model.endDrag() } })
    }

    private var swatches: some View {
        HStack(spacing: 10) {
            ForEach(LayoutBackground.allCases, id: \.self) { background in
                let selected = model.document.background == background
                Button { model.setBackground(background) } label: {
                    Circle().fill(background.color)
                        .overlay(Circle().strokeBorder(Theme.placeholderGlyph.color.opacity(0.5), lineWidth: 1))
                        .overlay(Circle().strokeBorder(Theme.accent.color, lineWidth: 2).padding(-4).opacity(selected ? 1 : 0))
                        .frame(width: 28, height: 28).padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: background.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Captions and export

    private var captions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Include captions", isOn: Binding(get: { model.document.showsCaptions }, set: model.setCaptions))
            if model.document.showsCaptions {
                TextField("Title", text: Binding(get: { model.document.title }, set: model.setTitle))
                    .textFieldStyle(.roundedBorder)
                TextField("Note", text: Binding(get: { model.document.note }, set: model.setNote))
                    .textFieldStyle(.roundedBorder)
            }
            if model.document.kind == .contactSheet {
                Toggle("File names under photos", isOn: Binding(get: { model.document.showsFileNames }, set: model.setFileNames))
            }
        }
    }

    private var resolution: some View {
        Picker("Resolution", selection: Binding(get: { model.document.resolution }, set: model.setResolution)) {
            ForEach(ExportResolution.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
        }
        .pickerStyle(.menu)
    }
}

/// A tile with a drawn icon and a caption. The chosen tile has an accent ring and the selected trait.
private struct LayoutChoiceTile<Content: View>: View {
    let selected: Bool
    let label: Text
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                content.frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent.color : Theme.placeholderFill.color,
                                                                       lineWidth: selected ? 2 : 1))
                label.font(.system(size: 11)).foregroundStyle(selected ? Theme.accent.color : Theme.textSecondary.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Gray rectangles that show a preset. The cells share the space like the layout engine does.
private struct PresetPreview: View {
    let node: SplitNode

    var body: some View {
        Self.view(node).padding(.horizontal, 6)
    }

    private static func view(_ node: SplitNode) -> AnyView {
        switch node {
        case .cell:
            AnyView(Rectangle().fill(Theme.placeholderGlyph.color.opacity(0.6)))
        case .row(let children):
            AnyView(HStack(spacing: 2) { ForEach(children.indices, id: \.self) { view(children[$0]) } })
        case .column(let children):
            AnyView(VStack(spacing: 2) { ForEach(children.indices, id: \.self) { view(children[$0]) } })
        }
    }
}
