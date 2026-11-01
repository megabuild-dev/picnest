import PicnestCore
import SwiftUI

extension AspectRatio {
    var label: Text {
        switch self {
        case .original: Text("Original")
        case .freeform: Text("Freeform")
        case .square: Text("Square")
        case .fourThree: Text(verbatim: "4:3")
        case .threeTwo: Text(verbatim: "3:2")
        case .sixteenNine: Text(verbatim: "16:9")
        }
    }
}

extension AdjustmentKind {
    var title: LocalizedStringKey {
        switch self {
        case .exposure: "Exposure"
        case .contrast: "Contrast"
        case .warmth: "Warmth"
        case .saturation: "Saturation"
        }
    }
}

/// The right panel: aspect ratio, straighten, rotate and flip, adjustments. It scrolls to the section of the tool.
struct EditorPanel: View {
    @Bindable var model: PhotoEditorViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Aspect ratio") { aspect }.id(EditorTool.crop)
                    Divider()
                    section("Straighten") { straighten }.id(EditorTool.straighten)
                    Divider()
                    section("Rotate & flip") { rotateAndFlip }.id(EditorTool.rotate)
                    Divider()
                    section("Adjustments") { adjustments }.id(EditorTool.adjust)
                }
                .padding(20)
            }
            .onChange(of: model.tool) { _, tool in
                if reduceMotion {
                    proxy.scrollTo(tool, anchor: .top)
                } else {
                    withAnimation { proxy.scrollTo(tool, anchor: .top) }
                }
            }
        }
        .frame(width: Theme.Metrics.editorPanel)
        .background(Theme.surface.color)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
    }

    private var aspect: some View {
        HStack {
            Picker("Aspect ratio", selection: Binding(get: { model.edit.aspect }, set: model.setAspect)) {
                ForEach(AspectRatio.allCases, id: \.self) { $0.label.tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer(minLength: 0)
            Text(verbatim: model.outputSizeText)
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.textSecondary.color)
                .accessibilityLabel(Text("Output size"))
        }
    }

    private var straighten: some View {
        valueSlider(
            "Straighten", value: Binding(get: { model.edit.straighten }, set: model.setStraighten),
            range: -45...45, step: 0.1, text: PhotoEditorViewModel.straightenText(model.edit.straighten))
    }

    private var rotateAndFlip: some View {
        HStack(alignment: .top, spacing: 8) {
            tile("Rotate left", symbol: "rotate.left") { model.rotate(clockwise: false) }
                .keyboardShortcut("r", modifiers: .command)
            tile("Rotate right", symbol: "rotate.right") { model.rotate(clockwise: true) }
                .keyboardShortcut("r", modifiers: [.command, .option])
            tile("Flip horizontal", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                model.flip(horizontal: true)
            }
            tile("Flip vertical", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                model.flip(horizontal: false)
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18)).frame(height: 36)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.placeholderFill.color))
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary.color)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private var adjustments: some View {
        VStack(spacing: 12) {
            ForEach(AdjustmentKind.allCases, id: \.self) { kind in
                valueSlider(
                    kind.title,
                    value: Binding(get: { Double(model.edit[kind]) }, set: { model.setAdjustment(kind, Int($0.rounded())) }),
                    range: -100...100, step: 1, text: PhotoEditorViewModel.adjustmentText(model.edit[kind]))
            }
        }
    }

    /// A slider with its value at the right. VoiceOver reads the value. The end of a drag is 1 undo step.
    private func valueSlider(
        _ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String
    ) -> some View {
        HStack(spacing: 8) {
            if title != "Straighten" {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
                    .frame(width: 70, alignment: .leading)
            }
            Slider(value: value, in: range, step: step) { editing in
                if !editing { model.endDrag() }
            }
            .tint(Theme.accent.color)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(verbatim: text))
            Text(verbatim: text).font(.system(size: 12)).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
