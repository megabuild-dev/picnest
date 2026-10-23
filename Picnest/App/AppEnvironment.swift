import Foundation
import PicnestCore

/// Makes every repository and service 1 time and shares them with the view models.
/// There is exactly 1 `SortService` (its busy guard is per instance), 1 `ScanService`
/// (its embedder and embedding caches are per instance), 1 `TrashService` (shared with every review through
/// the library), 1 `LibraryService`, and 1 `ThumbnailService`
/// (its memory cache is per instance).
@MainActor
final class AppEnvironment {
    /// Info.plist key that holds the model stem. Its value comes from `PICNEST_MODEL_STEM` in
    /// `project.yml`, the 1 place that sets the model size (the build copies those model files).
    nonisolated static let modelStemKey = "PicnestModelStem"

    let sessions: SessionRepository
    let bookmarks: BookmarkRepository
    let scanService: ScanService
    let sortService: SortService
    let classifyService: ClassifyService
    let trashService: TrashService
    let library: LibraryService
    let thumbnails: ThumbnailService

    /// The app environment: the bundled Core ML model, Application Support, and standard defaults.
    /// The model loads on first use, not here.
    convenience init() {
        let size = Self.modelSize(in: .main)
        let modelDirectory = (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appending(path: "Models", directoryHint: .isDirectory)
        self.init(
            makeEmbedder: { try CoreMLEmbedder(size: size, modelDirectory: modelDirectory) },
            sessions: SessionRepository(),
            defaults: .standard)
    }

    /// Test environment: a fake embedder, a temporary sessions folder, and a private defaults suite.
    /// `sortFileOps` lets a test hold a sort or an undo while it runs.
    convenience init(embedder: any Embedder, sessionsRoot: URL, defaults: UserDefaults,
                     sortFileOps: any FileOps = LocalFileOps()) {
        self.init(makeEmbedder: { embedder }, sessions: SessionRepository(root: sessionsRoot), defaults: defaults,
                  sortFileOps: sortFileOps)
    }

    private init(
        makeEmbedder: @escaping @Sendable () throws -> any Embedder,
        sessions: SessionRepository,
        defaults: UserDefaults,
        sortFileOps: any FileOps = LocalFileOps()
    ) {
        self.sessions = sessions
        bookmarks = BookmarkRepository(defaults: defaults)
        classifyService = ClassifyService(settings: .default)
        scanService = ScanService(makeEmbedder: makeEmbedder, sessions: sessions, settings: .default)
        sortService = SortService(fileOps: sortFileOps)
        trashService = TrashService(fileOps: LocalFileOps())
        let images = ImageRepository()  // 1 instance, so the app has 1 thumbnail cache.
        library = LibraryService(
            sessions: sessions, bookmarks: bookmarks, scanService: scanService, classify: classifyService,
            sortService: sortService, trashService: trashService, images: images)
        thumbnails = ThumbnailService(images: images)
    }

    /// The model size from the bundle's Info.plist. A missing or unknown stem is a build error, so stop.
    nonisolated static func modelSize(in bundle: Bundle) -> MobileCLIPSize {
        guard let stem = bundle.object(forInfoDictionaryKey: modelStemKey) as? String else {
            fatalError("Info.plist has no \(modelStemKey). Set PICNEST_MODEL_STEM in project.yml.")
        }
        guard let size = MobileCLIPSize(modelStem: stem) else {
            fatalError("Unknown model stem \"\(stem)\" in \(modelStemKey). Check PICNEST_MODEL_STEM.")
        }
        return size
    }
}
