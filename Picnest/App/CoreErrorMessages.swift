import Foundation
import PicnestCore

/// The user texts for errors of `PicnestCore`. The core has no UI text, so the app maps each error here.
/// `SortError` has its own mapping in `SortMessages`. An error with no mapping keeps its `localizedDescription`.
enum CoreErrorMessages {
    static func text(for error: any Error) -> String {
        switch error {
        case let error as SortError:
            return SortMessages.text(for: error)
        case let error as TrashError:
            return text(for: error)
        case EmbedderError.unreadable(let url):
            return String(localized: "Picnest could not read “\(url.lastPathComponent)”.")
        case let failure as CoreMLEmbedder.Failure:
            switch failure {
            case .missingModel: return String(localized: "The model of Picnest is missing. Install Picnest again.")
            case .unexpectedModel: return String(localized: "The model of Picnest has an unexpected format. Install Picnest again.")
            }
        case is CLIPTokenizer.Failure, is CandidateRepository.LoadError:
            return String(localized: "A file of the model is missing or damaged. Install Picnest again.")
        default:
            return error.localizedDescription
        }
    }

    /// The alert text of a photo that did not go to the Trash, or did not come back from it.
    static func text(for error: TrashError) -> String {
        switch error {
        case .cannotTrash(_, let reason):
            return String(localized: "The photo could not be moved to the Trash: \(localizedReason(reason)).")
        case .cannotPutBack(_, let reason):
            return String(localized: "The photo could not be put back: \(localizedReason(reason)).")
        }
    }

    /// The reasons that `TrashService` gives are English text of the core. The app translates the 3 known ones.
    private static func localizedReason(_ reason: String) -> String {
        let trimmed = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
        switch trimmed {
        case "the file is not in the Trash any more": return String(localized: "the file is not in the Trash any more")
        case "a file already exists at its original place": return String(localized: "a file already exists at its original place")
        case "its place in the Trash is not known": return String(localized: "its place in the Trash is not known")
        default: return trimmed
        }
    }
}
