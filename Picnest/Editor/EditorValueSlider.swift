import SwiftUI

/// A slider with its value at the right. VoiceOver reads the value as text. `onEditing` tells the start and the end
/// of a drag, so the editor can make the drag 1 undo step. Shared by the photo editor and the layout editor.
struct EditorValueSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let showsLabel: Bool
    let text: String
    let onEditing: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsLabel {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.textSecondary.color)
                    .frame(width: 70, alignment: .leading)
            }
            Slider(value: $value, in: range, step: step, onEditingChanged: onEditing)
                .tint(Theme.accent.color)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(verbatim: text))
            Text(verbatim: text).font(.system(size: 12)).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
