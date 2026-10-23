import Foundation
import Synchronization

/// Events of the scan screen (spec 3.2).
public enum ScanEvent: Sendable {
    case preparingModel
    case embedding(done: Int, total: Int)
    case finished(Session)
}

/// Scans a source folder, embeds its photos, and proposes categories (spec 4.3).
public final class ScanService: Sendable {
    static let seed: UInt64 = 42

    private let makeEmbedder: @Sendable () throws -> any Embedder
    private let sessions: SessionRepository
    private let candidates: CandidateRepository
    private let media: MediaRepository
    private let classifier: ClassifyService
    private let embedder = Mutex<(any Embedder)?>(nil)
    private let repositories = Mutex<[URL: EmbeddingRepository]>([:])

    public init(
        makeEmbedder: @escaping @Sendable () throws -> any Embedder,
        sessions: SessionRepository,
        candidates: CandidateRepository = .init(),
        media: MediaRepository = .init(),
        settings: ClassifySettings = .default
    ) {
        self.classifier = ClassifyService(settings: settings)
        self.makeEmbedder = makeEmbedder
        self.sessions = sessions
        self.candidates = candidates
        self.media = media
    }

    /// The candidate list of every scan: **All topics** (spec 4.3, phase 12).
    static let candidateList = CandidateList.all

    /// Emits `.preparingModel`, then `.embedding` progress, then `.finished` after the session is saved.
    /// Cancelling the consumer's task cancels the work. Categories are named from **All topics**.
    public func firstScan(source: URL) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try await self.runFirstScan(source: source) { continuation.yield($0) }
                    continuation.yield(.finished(session))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Scans again and keeps the review work (spec 5.1). Only new and changed images are embedded.
    /// Categories, manual picks, held Not sure photos, and Don't move photos stay. States and
    /// examples of removed files are dropped. Runs clustering only when the session has no categories:
    /// it then proposes them from the kept readable images, as a first scan does. Don't move photos stay.
    /// Trashed photos leave the session (spec 7.4): one whose file is not at its original path is dropped,
    /// and one that is there again (put back with Finder) is scanned as a new photo.
    public func rescan(_ s: Session, source: URL) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try await self.runRescan(s, source: source) { continuation.yield($0) }
                    continuation.yield(.finished(session))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The embedding repository of a source, made with the shared embedder. The same source gets
    /// the same repository, so its cache has 1 writer.
    public func embeddingRepository(for source: URL) throws -> EmbeddingRepository {
        let embedder = try loadEmbedder()
        let directory = sessions.directory(for: source)
        return repositories.withLock { stored in
            if let existing = stored[directory] { return existing }
            let made = EmbeddingRepository(embedder: embedder, cacheDirectory: directory)
            stored[directory] = made
            return made
        }
    }

    // MARK: - Steps

    private func runFirstScan(
        source: URL, emit: @escaping @Sendable (ScanEvent) -> Void
    ) async throws -> Session {
        emit(.preparingModel)
        let repository = try embeddingRepository(for: source)
        try Task.checkCancellation()

        let scan = try media.scan(source: source, excluding: [SortOptions.defaults(source: source).destination])
        let (vectors, unreadable) = try await repository.embeddings(for: scan.media, source: source) { done, total in
            emit(.embedding(done: done, total: total))
        }

        var fixed: [MediaID: PhotoState] = [:]
        for id in unreadable { fixed[id] = .unreadable }
        let (categories, classified) = try await proposeAndClassify(
            scan.media.map(\.id), vectors: vectors, fixed: fixed, repository: repository)

        let session = Session(
            sourcePath: source.path(percentEncoded: false), candidateList: Self.candidateList,
            categories: categories, states: classified, scan: scan, sortedAt: nil)
        try Task.checkCancellation()
        try sessions.save(session)
        return session
    }

    private func runRescan(
        _ old: Session, source: URL, emit: @escaping @Sendable (ScanEvent) -> Void
    ) async throws -> Session {
        emit(.preparingModel)
        let repository = try embeddingRepository(for: source)
        try Task.checkCancellation()

        let scan = try media.scan(source: source, excluding: [SortOptions.defaults(source: source).destination])
        let (vectors, unreadable) = try await repository.embeddings(for: scan.media, source: source) { done, total in
            emit(.embedding(done: done, total: total))
        }

        // A trashed photo keeps no old state or example: if it is found again, it is a new photo.
        let kept = Set(scan.media.map(\.id)).subtracting(old.trashedIDs)
        var categories = old.categories
        for i in categories.indices { categories[i].exampleIDs.removeAll { !kept.contains($0) } }

        var states: [MediaID: PhotoState] = [:]
        for (id, state) in old.states where kept.contains(id) {
            switch state {
            case .manual, .heldNotSure, .dontMove: states[id] = state
            case .auto, .unreadable: break  // Classified again below, or marked unreadable.
            }
        }
        for id in unreadable where states[id] == nil { states[id] = .unreadable }

        let classified: [MediaID: PhotoState]
        if categories.isEmpty {
            // A session with no categories (phase 11): propose them as a first scan does. Only Don't move
            // and unreadable states can exist without a category.
            let fixed = states.filter { $0.value == .dontMove || $0.value == .unreadable }
            (categories, classified) = try await proposeAndClassify(
                scan.media.map(\.id).filter(kept.contains), vectors: vectors, fixed: fixed,
                repository: repository)
        } else {
            var prompts: [CategoryID: [Vector]] = [:]
            for category in categories {
                prompts[category.id] = try await repository.textEmbeddings(category.prompts)
            }
            classified = classifier.classify(
                states: states, categories: categories, images: vectors, prompts: prompts)
        }

        var session = old
        session.categories = categories
        session.states = classified
        session.scan = scan
        // A trashed photo found at its original path was classified above as new. One not found is not
        // in `scan`. Either way, it is no longer trashed.
        session.trashed = []
        try Task.checkCancellation()
        try sessions.save(session)
        return session
    }

    /// Creates the embedder on first use and keeps it for later scans.
    private func loadEmbedder() throws -> any Embedder {
        try embedder.withLock { stored in
            if let stored { return stored }
            let made = try makeEmbedder()
            stored = made
            return made
        }
    }

    /// Proposes categories from the readable images among `ids` (those in `vectors`), gives each 1 an auto
    /// state for its cluster, puts `fixed` over those states, and classifies every image in `vectors`.
    /// The first scan and the rescan of a session with no categories use it.
    private func proposeAndClassify(
        _ ids: [MediaID], vectors: [MediaID: Vector], fixed: [MediaID: PhotoState],
        repository: EmbeddingRepository
    ) async throws -> (categories: [Category], states: [MediaID: PhotoState]) {
        let ids = ids.filter { vectors[$0] != nil }
        let proposal = try await proposeCategories(
            ids.map { vectors[$0]! }, candidates: candidates.load(Self.candidateList), repository: repository)

        var states: [MediaID: PhotoState] = [:]
        for (id, cluster) in zip(ids, proposal.labels) {
            states[id] = .auto(Assignment(
                categoryID: proposal.categoryIDs[cluster], score: 0, secondCategoryID: nil, secondScore: nil,
                percent: 0, uncertain: false))
        }
        states.merge(fixed) { _, new in new }

        let classified = classifier.classify(
            states: states, categories: proposal.categories, images: vectors, prompts: proposal.prompts)
        return (proposal.categories, classified)
    }

    /// Clusters `vectors` and names each cluster with the candidate whose best prompt has the
    /// highest cosine with the normalized cluster center. Categories are ordered by merged size,
    /// largest first. Clusters that get the same candidate merge into one category.
    /// `categoryIDs[label]` is the category of cluster `label`.
    private func proposeCategories(
        _ vectors: [Vector], candidates: [Candidate], repository: EmbeddingRepository
    ) async throws -> (categories: [Category], categoryIDs: [CategoryID], labels: [Int], prompts: [CategoryID: [Vector]]) {
        let result: (k: Int, labels: [Int])
        if let range = Clustering.kRange(for: vectors.count) {
            result = Clustering.bestK(vectors, range: range, seed: Self.seed)
        } else {
            result = (vectors.isEmpty ? 0 : 1, Array(repeating: 0, count: vectors.count))
        }
        guard result.k > 0 else { return ([], [], result.labels, [:]) }
        // The bundled lists are never empty. Keep a fallback so every cluster still gets a category.
        let candidates = candidates.isEmpty ? [Candidate(displayName: "Photos", emoji: "🖼️", prompts: [])] : candidates

        let (centers, sizes) = Clustering.centers(vectors, labels: result.labels, k: result.k)
        let promptVectors = try await repository.candidateVectors(candidates)
        let scores = Clustering.candidateScores(centers: centers, promptVectors: promptVectors)

        // Name each cluster, then merge clusters that got the same candidate into one category.
        let bestCandidate = scores.map { Clustering.bestCandidate($0) ?? 0 }
        var groupSize: [Int: Int] = [:]
        var firstCluster: [Int: Int] = [:]
        for cluster in 0..<result.k {
            groupSize[bestCandidate[cluster], default: 0] += sizes[cluster]
            firstCluster[bestCandidate[cluster]] = firstCluster[bestCandidate[cluster]] ?? cluster
        }
        let ordered = groupSize.keys.sorted {
            groupSize[$0]! != groupSize[$1]! ? groupSize[$0]! > groupSize[$1]! : firstCluster[$0]! < firstCluster[$1]!
        }
        var categories: [Category] = []
        var categoryPrompts: [CategoryID: [Vector]] = [:]
        var categoryOfCandidate: [Int: CategoryID] = [:]
        for (order, index) in ordered.enumerated() {
            let candidate = candidates[index]
            let category = Category(
                id: UUID(), displayName: candidate.displayName, emoji: candidate.emoji,
                prompts: candidate.prompts, exampleIDs: [], order: order)
            categories.append(category)
            categoryPrompts[category.id] = promptVectors[index]
            categoryOfCandidate[index] = category.id
        }
        let categoryIDs = bestCandidate.map { categoryOfCandidate[$0]! }
        return (categories, categoryIDs, result.labels, categoryPrompts)
    }
}
