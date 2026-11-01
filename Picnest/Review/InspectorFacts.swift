import Foundation
import PicnestCore

/// What the inspector shows for 1 photo (spec 6). No pixel size here: it loads later, off the main thread.
struct InspectorFacts: Equatable {
    enum Status: Equatable {
        case category(emoji: String, name: String)
        case notSure
        case staysHere
        case none
    }

    struct Suggestion: Equatable {
        let categoryName: String
        let alternativeName: String?
        let alternativePercent: Int?
    }

    let id: MediaID
    let name: String
    let status: Status
    /// The date that the grid shows, or nil when only the modification time is known.
    let date: Date?
    let fileSize: Int64
    /// The percent of the app's guess. Nil for a photo that the user chose by hand, and for one with no guess.
    let confidence: Int?
    let isChosenByYou: Bool
    /// Set for a photo in Not sure.
    let suggestion: Suggestion?
    let isUncertain: Bool
}
