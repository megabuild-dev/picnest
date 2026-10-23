import CoreGraphics
import Foundation
import Observation
import PicnestCore

/// State of the Suggest Categories sheet (spec 3.7). Talks to `ReviewService` only. Photo thumbnails
/// come from `thumbnail`, which is the `ThumbnailService` path of the Review screen.
@MainActor
@Observable
final class SuggestViewModel: Identifiable {
    enum State: Equatable {
        case loading, ready, empty
        case failed(String)
    }

    /// 1 suggestion, with the fields that the user can change.
    struct Row: Identifiable, Equatable {
        let suggestion: CategorySuggestion
        var isOn = true
        var name: String
        var emoji: String
        /// The last emoji that passed `isSingleEmoji`.
        fileprivate(set) var lastGoodEmoji: String

        init(_ suggestion: CategorySuggestion) {
            self.suggestion = suggestion
            name = suggestion.name
            emoji = suggestion.emoji
            lastGoodEmoji = suggestion.emoji
        }

        var id: UUID { suggestion.id }
        var ids: [MediaID] { suggestion.ids }
    }

    static let emptyText = "No new groups found. Move the photos by hand or make a category with New Category…"
    static let thumbnailsPerRow = 4

    private(set) var state: State = .loading
    var rows: [Row] = []

    @ObservationIgnored private let review: ReviewService
    @ObservationIgnored private let thumbnailLoader: (MediaID, Int) async -> CGImage?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let onAdded: ([CategoryID]) -> Void
    @ObservationIgnored private var hasLoaded = false

    /// `onAdded` gets the ids of the new categories, so the screen can close the sheet.
    init(review: ReviewService, thumbnail: @escaping (MediaID, Int) async -> CGImage?, locale: Locale = .current,
         onAdded: @escaping ([CategoryID]) -> Void = { _ in }) {
        self.review = review
        thumbnailLoader = thumbnail
        self.locale = locale
        self.onAdded = onAdded
    }

    /// Finds the groups. Runs once per sheet. Closing the sheet cancels the task that calls it.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        state = .loading
        do {
            let suggestions = try await review.suggestCategories()
            try Task.checkCancellation()
            rows = suggestions.map(Row.init)
            state = rows.isEmpty ? .empty : .ready
        } catch is CancellationError {
            // The sheet closed.
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Call when editing of the emoji field ends. An entry that is not exactly 1 emoji goes back to the
    /// last good emoji, so the field shows what `add()` makes.
    func commitEmoji(of id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let emoji = rows[i].emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if ReviewViewModel.isSingleEmoji(emoji) {
            rows[i].emoji = emoji
            rows[i].lastGoodEmoji = emoji
        } else {
            rows[i].emoji = rows[i].lastGoodEmoji
        }
    }

    func thumbnail(_ id: MediaID, maxPixel: Int) async -> CGImage? {
        await thumbnailLoader(id, maxPixel)
    }

    // MARK: - Texts and checks

    var checkedCount: Int { rows.filter(\.isOn).count }

    /// "Add 1 Category" or "Add <N> Categories".
    var addTitle: String {
        let n = checkedCount
        return n == 1 ? "Add 1 Category" : "Add \(n.formatted(.number.locale(locale))) Categories"
    }

    /// The red hint under the name of a checked row, or nil. An unchecked row has no hint.
    func nameHint(for row: Row) -> String? {
        guard row.isOn else { return nil }
        let name = Self.key(row.name)
        guard !name.isEmpty else { return "Enter a name." }
        if review.session.categories.contains(where: { Self.key($0.displayName) == name }) { return Self.used }
        let others = rows.filter { $0.isOn && $0.id != row.id }
        return others.contains { Self.key($0.name) == name } ? Self.used : nil
    }

    var canAdd: Bool {
        checkedCount > 0 && rows.allSatisfy { nameHint(for: $0) == nil }
    }

    /// Makes the checked rows into categories (1 undo step), then calls `onAdded`.
    func add() {
        guard canAdd else { return }
        let suggestions = rows.filter(\.isOn).map { row -> CategorySuggestion in
            var s = row.suggestion
            s.name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let emoji = row.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            s.emoji = ReviewViewModel.isSingleEmoji(emoji) ? emoji : row.lastGoodEmoji
            return s
        }
        onAdded(review.addSuggested(suggestions))
    }

    private static let used = "This name is already used."

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
