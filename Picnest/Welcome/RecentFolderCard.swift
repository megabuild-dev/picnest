import SwiftUI

/// One recent folder on the Welcome screen: short path, photo count, state, **Open**, and Undo Last Sort.
/// The card has no saved-session data yet, so its main action is **Open**, not **Continue**.
struct RecentFolderCard: View {
    let name: String
    let path: String
    let count: String
    /// "Sorted <date>", or nil.
    let sorted: String?
    let canUndo: Bool
    let isUndoing: Bool
    let open: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.accent.color)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.selection.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.color)
                    .lineLimit(1)
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.color)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(name))
            .accessibilityValue(Text(detail))
            Spacer(minLength: 8)
            if isUndoing {
                ProgressView().controlSize(.small)
            } else if canUndo {
                Button("Undo Last Sort", action: undo)
                    .controlSize(.small)
                    .help("Put the photos of the last sort back")
            }
            Button("Open", action: open)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent.color)
                .accessibilityLabel(Text("Open \(name)"))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.textSecondary.color.opacity(0.18)))
    }

    private var detail: String {
        [count, sorted].compactMap { $0 }.joined(separator: " · ")
    }
}
