import PicnestCore
import SwiftUI

/// Review screen (spec 3.3): the sidebar, a compact 1-row toolbar, and the photo grid.
struct ReviewView: View {
    @State private var model: ReviewViewModel
    @State private var newCategoryName = ""
    /// The open Sort sheet, or nil.
    @State private var sort: SortViewModel?
    @State private var isOpeningSort = false
    /// Set by the hint of the Sort sheet; the suggest sheet opens when the Sort sheet is gone.
    @State private var suggestAfterSort = false

    private let review: ReviewService
    private let sortService: SortService
    private let library: LibraryService
    private let app: AppModel

    /// The view model is made once per screen, in the `@State` initializer. `app` scans again
    /// (`rescan`) and closes the session after a sort (`done`, spec 9.1). `afterScan` is true when a scan
    /// opened this review (spec 3.7).
    init(review: ReviewService, classify: ClassifyService, thumbnails: ThumbnailService, sortService: SortService,
         library: LibraryService, app: AppModel, afterScan: Bool = false) {
        self.review = review
        self.sortService = sortService
        self.library = library
        self.app = app
        _model = State(initialValue: ReviewViewModel(
            review: review, classify: classify, thumbnails: thumbnails, library: library, app: app,
            afterScan: afterScan, onRescan: app.rescan))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
                .background(.background)
                .toolbar(removing: .title)
                .toolbar { toolbar }
        }
        .alert("New Category", isPresented: Bindable(model).isNamingNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Create") { model.createNewCategory(name: newCategoryName) }
            Button("Cancel", role: .cancel) { model.cancelNewCategory() }
        } message: {
            Text(model.newCategoryMovesPhotos ? "The selected photos go to the new category." : "Name the new category.")
        }
        .sheet(item: $sort, onDismiss: {
            if suggestAfterSort {
                suggestAfterSort = false
                model.openSuggest()
            }
        }) { SortSheet(model: $0) }
        .sheet(item: Bindable(model).suggest) { SuggestSheet(model: $0) }
        .alert("Undo Last Sort", isPresented: undoMessageBinding) {
            Button("OK", role: .cancel) { model.undoSortMessage = nil }
        } message: {
            Text(model.undoSortMessage ?? "")
        }
        // File > Start Over… (spec 3.3).
        .confirmationDialog("Start over?", isPresented: Bindable(model).isConfirmingStartOver,
                            titleVisibility: .visible) {
            Button("Start Over", role: .destructive) { Task { await model.startOver() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.startOverMessage)
        }
        .alert("Start Over", isPresented: startOverErrorBinding) {
            Button("OK", role: .cancel) { model.startOverErrorMessage = nil }
        } message: {
            Text(model.startOverErrorMessage ?? "")
        }
        .alert(model.trashAlertTitle, isPresented: trashMessageBinding) {
            Button("OK", role: .cancel) { model.trashMessage = nil }
        } message: {
            Text(model.trashMessage ?? "")
        }
        .alert("Rename Folder", isPresented: folderErrorBinding) {
            Button("OK", role: .cancel) { model.dismissFolderError() }
        } message: {
            Text(model.folderErrorMessage ?? "")
        }
        // A failed save (final review I4). Both buttons clear or replace the error themselves.
        .alert("Picnest could not save", isPresented: saveErrorBinding) {
            Button("Try Again") { model.retrySave() }
            Button("OK", role: .cancel) { model.dismissSaveError() }
        } message: {
            Text(model.saveErrorMessage ?? "")
        }
        // A failed organize (spec 7.2).
        .alert("Could not organize", isPresented: organizeErrorBinding) {
            Button("OK", role: .cancel) { model.dismissOrganizeError() }
        } message: {
            Text(model.organizeErrorMessage ?? "")
        }
        // The suggest sheet opens by itself once after a scan (spec 3.7).
        .task { model.suggestAfterScanIfNeeded() }
        .onChange(of: model.isNamingNewCategory) { if model.isNamingNewCategory { newCategoryName = "" } }
        // Edit > Undo and Redo act on this review (ReviewCommands).
        .focusedSceneValue(\.review, model)
        .overlay { organizingOverlay }
    }

    /// A blocking overlay while **Done** moves the classified photos into category folders (spec 7.2).
    @ViewBuilder private var organizingOverlay: some View {
        if model.isOrganizing {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 10) {
                    Text("Organizing photos…").font(.system(size: 13, weight: .semibold))
                    if let progress = model.organizeProgress, progress.total > 0 {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .frame(width: 240)
                        Text("\(progress.done.formatted()) / \(progress.total.formatted())")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.selectedItem {
        case .notSure:
            NotSureView(model: model)
        case .duplicates:
            DuplicatesView(model: model.duplicates)
        default:
            PhotoGridView(model: model)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 10) {
                Text(model.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                CountChip(count: model.count, tint: chipTint)
                Text(model.sourcePathText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.sourcePathText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.selectedItem == .duplicates {
                CleanUpAllButton(model: model.duplicates)
            } else {
                SizeSlider(model: model)
                Picker("Sort Order", selection: Bindable(model).sortOrder) {
                    ForEach(ReviewViewModel.SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Sort order")
            }
            if model.canUndoLastSort {
                Button("Undo Last Sort", systemImage: "arrow.uturn.backward") {
                    Task { await model.undoLastSort() }
                }
                .labelStyle(.titleAndIcon)
                .disabled(!model.canSortOrRescan)
                .help("Put the photos of the last sort back")
            }
            Button("Rescan", systemImage: "arrow.clockwise", action: model.rescan)
                .labelStyle(.titleAndIcon)
                .disabled(!model.canSortOrRescan)
                .help("Scan the folder again and keep your changes")
            if model.selectedItem == .notSure && model.canSuggest {
                Button("Suggest Categories…", systemImage: "sparkles", action: model.openSuggest)
                    .labelStyle(.titleAndIcon)
                    .help("Find groups in the Not sure photos and make categories")
            }
            if model.selectedItem == .notSure && !model.notSureGroups.isEmpty {
                Button("Accept All Best Guesses", systemImage: "checkmark", action: model.acceptAll)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.tint)
                    .help("Move every Not sure photo to its best guess")
            }
            Button("Sort Photos…", action: openSort)
                .buttonStyle(.bordered)
                .disabled(isOpeningSort || !model.canSortOrRescan)
            Button("Done", action: model.done)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canDone)
                .help("Create a folder for each category, move the photos into it, and rename them")
        }
    }

    /// Makes the first plan from the latest review states, then shows the Sort sheet.
    private func openSort() {
        guard !isOpeningSort, model.canSortOrRescan else { return }
        isOpeningSort = true
        let sortModel = SortViewModel(review: review, sortService: sortService, library: library, onDone: app.done,
                                  onSuggest: { model.selectedItem = .notSure; suggestAfterSort = true; sort = nil })
        Task {
            await sortModel.load()
            sort = sortModel
            isOpeningSort = false
        }
    }

    private var undoMessageBinding: Binding<Bool> {
        Binding(get: { model.undoSortMessage != nil }, set: { if !$0 { model.undoSortMessage = nil } })
    }

    private var startOverErrorBinding: Binding<Bool> {
        Binding(get: { model.startOverErrorMessage != nil }, set: { if !$0 { model.startOverErrorMessage = nil } })
    }

    private var trashMessageBinding: Binding<Bool> {
        Binding(get: { model.trashMessage != nil }, set: { if !$0 { model.trashMessage = nil } })
    }

    private var folderErrorBinding: Binding<Bool> {
        Binding(get: { model.folderErrorMessage != nil }, set: { if !$0 { model.dismissFolderError() } })
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { model.saveErrorMessage != nil }, set: { _ in })
    }

    private var organizeErrorBinding: Binding<Bool> {
        Binding(get: { model.organizeErrorMessage != nil }, set: { if !$0 { model.dismissOrganizeError() } })
    }

    private var chipTint: Color {
        switch model.selectedItem {
        case .notSure: ReviewStyle.amber
        case .changedByYou: ReviewStyle.green
        case .category: .accentColor
        default: .secondary
        }
    }
}

/// The count next to the title, in a soft capsule.
private struct CountChip: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text(count.formatted())
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Thumbnail size: left is small (8 columns), right is large (2 columns).
private struct SizeSlider: View {
    let model: ReviewViewModel

    var body: some View {
        let range = ReviewViewModel.columnRange
        let size = Binding<Double>(
            get: { Double(range.upperBound + range.lowerBound - model.columns) },
            set: { model.columns = range.upperBound + range.lowerBound - Int($0.rounded()) })
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: size, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .frame(width: 90)
                .controlSize(.small)
            Image(systemName: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .help("Thumbnail size")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thumbnail size")
    }
}

#if DEBUG
/// Fake review data for the Xcode preview: 20 tiles with every badge kind. No real photos, so the
/// tiles show the gray placeholder.
@MainActor
enum ReviewPreviewData {
    struct NoEmbedder: Embedder {
        let dimension = 1
        func embedImages(_ urls: [URL]) async throws -> [Vector] { urls.map { _ in [1] } }
        func embedTexts(_ texts: [String]) async throws -> [Vector] { texts.map { _ in [1] } }
    }

    /// A library over a temporary sessions folder and a private defaults suite.
    static func library() -> LibraryService {
        let root = FileManager.default.temporaryDirectory.appending(path: "PicnestPreview", directoryHint: .isDirectory)
        let sessions = SessionRepository(root: root.appending(path: "Sessions"))
        let scan = ScanService(makeEmbedder: { NoEmbedder() }, sessions: sessions)
        return LibraryService(
            sessions: sessions, bookmarks: BookmarkRepository(defaults: UserDefaults(suiteName: "PicnestPreview")!),
            scanService: scan, classify: ClassifyService(), sortService: SortService())
    }

    /// An app model over a temporary sessions folder and a private defaults suite.
    static func app() -> AppModel {
        let root = FileManager.default.temporaryDirectory.appending(path: "PicnestPreview", directoryHint: .isDirectory)
        return AppModel(environment: AppEnvironment(
            embedder: NoEmbedder(), sessionsRoot: root.appending(path: "Sessions"),
            defaults: UserDefaults(suiteName: "PicnestPreview")!))
    }

    static func review() -> ReviewService {
        let root = FileManager.default.temporaryDirectory.appending(path: "PicnestPreview", directoryHint: .isDirectory)
        let art = PicnestCore.Category(
            id: UUID(), displayName: "Kids' artwork", emoji: "🎨", prompts: [], exampleIDs: [], order: 0)
        let outings = PicnestCore.Category(
            id: UUID(), displayName: "Family outings", emoji: "🌳", prompts: [], exampleIDs: [], order: 1)
        let documents = PicnestCore.Category(
            id: UUID(), displayName: "Documents", emoji: "🧾", prompts: [], exampleIDs: [], order: 2)
        let categories = [art, outings, documents]
        var media: [MediaFile] = []
        var states: [MediaID: PhotoState] = [:]
        var dates: [MediaID: PhotoDate] = [:]
        for i in 0..<20 {
            let name = i % 3 == 0 ? "IMG_\(5500 + i).HEIC" : "z79135052\(67100 + i)_a3f.jpg"
            let id = i == 19 ? "clip_\(i).mov" : name
            media.append(MediaFile(id: id, relativePath: id, kind: i == 19 ? .video : .image, size: 1,
                                   modified: Date(timeIntervalSince1970: 1_700_000_000)))
            dates[id] = PhotoDate(date: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400),
                                  source: i % 7 == 0 ? .modificationTime : .exif)
            let best = categories[i % 3], second = categories[(i + 1) % 3]
            func guess(_ percent: Int, uncertain: Bool) -> Assignment {
                Assignment(categoryID: best.id, score: 0.3, secondCategoryID: second.id, secondScore: 0.299,
                           percent: percent, uncertain: uncertain)
            }
            switch i {
            case 0..<8: states[id] = .auto(guess(70 + i * 3, uncertain: false))
            case 8..<12: states[id] = .auto(guess(38 + i, uncertain: true))
            case 12..<14: states[id] = .heldNotSure(guess(41, uncertain: true))
            case 14..<17: states[id] = .manual(best.id)
            case 17: states[id] = .dontMove
            case 18: states[id] = .unreadable
            default: break  // The video has no state.
            }
        }
        let session = Session(
            sourcePath: NSHomeDirectory() + "/Pictures/Zalo export", candidateList: .all,
            categories: categories, states: states, scan: ScanResult(media: media, dates: dates, skipped: [:]),
            sortedAt: nil)
        return ReviewService(
            session: session, source: URL(filePath: session.sourcePath, directoryHint: .isDirectory), images: [:],
            prompts: [:], classify: ClassifyService(), sessions: SessionRepository(root: root.appending(path: "Sessions")),
            embeddings: EmbeddingRepository(embedder: NoEmbedder(), cacheDirectory: root.appending(path: "Cache")))
    }
}

extension ReviewView {
    /// The preview with 2 selected photos, so the selection bar shows.
    fileprivate init(previewSelecting ids: [MediaID]) {
        self.init(review: ReviewPreviewData.review(), classify: ClassifyService(),
                  thumbnails: ThumbnailService(images: ImageRepository()),
                  sortService: SortService(), library: ReviewPreviewData.library(), app: ReviewPreviewData.app())
        let model = _model.wrappedValue
        for id in ids { model.click(id, modifiers: .command) }
    }
}

extension ReviewView {
    /// The Not sure view: 6 uncertain photos in 3 groups.
    fileprivate init(previewNotSure: Void) {
        self.init(review: ReviewPreviewData.review(), classify: ClassifyService(),
                  thumbnails: ThumbnailService(images: ImageRepository()),
                  sortService: SortService(), library: ReviewPreviewData.library(), app: ReviewPreviewData.app())
        _model.wrappedValue.selectedItem = .notSure
    }
}

#Preview("Not sure", traits: .fixedLayout(width: 1200, height: 800)) {
    ReviewView(previewNotSure: ())
}

#Preview("Review", traits: .fixedLayout(width: 1200, height: 800)) {
    ReviewView(previewSelecting: ["z7913505267108_a3f.jpg", "z7913505267110_a3f.jpg"])
}
#endif
