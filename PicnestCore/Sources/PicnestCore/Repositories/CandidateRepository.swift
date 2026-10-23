import Foundation

public struct CandidateRepository: Sendable {
    public enum LoadError: Error { case missingResource(String) }

    public init() {}

    public func load(_ list: CandidateList) throws -> [Candidate] {
        let name = Self.resourceName(list)
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw LoadError.missingResource(name)
        }
        return try JSONDecoder().decode([Candidate].self, from: Data(contentsOf: url))
    }

    private static func resourceName(_ list: CandidateList) -> String {
        switch list {
        case .all: "candidates-all"
        case .everyday: "candidates-everyday"
        case .artStudio: "candidates-art"
        }
    }
}
