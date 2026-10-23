import Foundation

public typealias CategoryID = UUID

public struct Category: Identifiable, Codable, Sendable, Hashable {
    public var id: CategoryID
    public var displayName: String
    public var emoji: String
    public var prompts: [String]
    public var exampleIDs: [MediaID]
    public var order: Int

    public init(id: CategoryID, displayName: String, emoji: String, prompts: [String], exampleIDs: [MediaID], order: Int) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.prompts = prompts
        self.exampleIDs = exampleIDs
        self.order = order
    }
}

public struct Candidate: Codable, Sendable, Hashable {
    public var displayName: String
    public var emoji: String
    public var prompts: [String]
    /// Old names of this entry (a merged synonym or a longer name), so an old session's category with that
    /// name counts as this entry (spec 4.8 step 4). Empty when the JSON has no `aliases`.
    public var aliases: [String]

    /// The display name, then the aliases.
    public var names: [String] { [displayName] + aliases }

    public init(displayName: String, emoji: String, prompts: [String], aliases: [String] = []) {
        self.displayName = displayName
        self.emoji = emoji
        self.prompts = prompts
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey { case displayName, emoji, prompts, aliases }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        emoji = try c.decode(String.self, forKey: .emoji)
        prompts = try c.decode([String].self, forKey: .prompts)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

/// A built-in candidate list. The app uses only `all` (**All topics**, spec 4.3). `everyday` and `artStudio`
/// stay so an old `session.json` still decodes and ModelBench still loads them.
public enum CandidateList: String, Codable, Sendable, Hashable { case all, everyday, artStudio }
