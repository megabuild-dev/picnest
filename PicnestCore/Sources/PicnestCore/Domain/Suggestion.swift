import Foundation

/// A new category that the app suggests for a group of "Not sure" photos (spec 3.7, 4.8).
/// A "Group <n>" suggestion has the emoji 📁 and no prompts. When the user adds it, it gets the
/// prompt "a photo of <name>" with the name the user gave it.
public struct CategorySuggestion: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var prompts: [String]
    /// The photos of the suggestion, sorted.
    public var ids: [MediaID]

    public init(id: UUID = UUID(), name: String, emoji: String, prompts: [String], ids: [MediaID]) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.prompts = prompts
        self.ids = ids
    }
}
