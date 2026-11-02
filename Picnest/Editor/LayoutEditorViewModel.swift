import CoreGraphics
import Foundation
import Observation
import PicnestCore

/// A photo that the left panel of the layout editor lists.
struct LayoutPhoto: Identifiable, Hashable {
    let id: MediaID
    let fileName: String
}

/// A list of photos that the left panel can show: **All Photos**, a category, or a collection.
/// The review makes the options. The layout editor does not read the session.
struct LayoutSourceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let photos: [LayoutPhoto]
}

/// The state and the actions of the layout editor (UI redesign, Phase 5). It holds the layout with its undo
/// history, the pages and their preview, the left panel, and the export. The layout is a draft that saves
/// by itself. The export never changes a photo.
@MainActor @Observable
final class LayoutEditorViewModel: EditorSession {
    /// The `UserDefaults` key of the last export folder.
    nonisolated static let exportFolderKey = "layoutExportFolder"
    static let zoomRange: ClosedRange<Double> = 0.25...4
    private static let zoomStep = 1.25
    /// The longest side of a preview, in pixels.
    private static let maxPreviewPixel = 2400

    /// The field that has a change that waits for its end.
    private enum Slider: Equatable {
        case spacing, margin, title, note
    }

    private(set) var pages: [LayoutPage]
    private(set) var pageIndex = 0
    private(set) var pageImage: CGImage?
    /// The index of the selected cell in the whole layout, or nil.
    private(set) var selectedCell: Int?
    /// True until the user zooms in or out: the page then shows at `fitScale`.
    private(set) var fitsPage = true
    /// The scale after a zoom, as a fraction of the actual size (1 is 100%). Used while `fitsPage` is false.
    private var chosenScale: Double = 1
    private(set) var isPreviewing = false
    private(set) var isExporting = false
    var exportError: String?
    /// The files of the last good export.
    private(set) var lastExport: [URL] = []
    private(set) var sourceID: String
    var searchText = ""
    /// The width of the page area in points. The preview has twice this width in pixels, up to 2400.
    var canvasWidth: Double = 800 {
        didSet { if canvasWidth != oldValue { refreshPreview() } }
    }
    /// The height of the page area in points. It changes `fitScale` only.
    var canvasHeight: Double = 600

    private var history: History<LayoutDocument>
    @ObservationIgnored private lazy var pending = PendingCommit<Slider> { [weak self] in self?.history.commit() }
    @ObservationIgnored nonisolated(unsafe) private var draftTask: Task<Void, Never>?
    @ObservationIgnored private let previews = PreviewChain()
    /// How long a slider or text change that has no end event waits for the next one before it is 1 undo step.
    @ObservationIgnored var commitDelay: Duration {
        get { pending.delay }
        set { pending.delay = newValue }
    }
    /// How long the draft waits after a change before it saves. A test hook.
    @ObservationIgnored var draftDelay: Duration = .seconds(1)

    @ObservationIgnored private let sources: [LayoutSourceOption]
    @ObservationIgnored private let service: LayoutExportService
    @ObservationIgnored private let source: URL
    /// Builds the files that no export may replace, at write time (final review C1).
    @ObservationIgnored private let protectedFiles: @MainActor () -> ProtectedFiles
    @ObservationIgnored private var fileNames: [MediaID: String]
    @ObservationIgnored private let saveDraft: @MainActor (LayoutDocument?) -> Void
    @ObservationIgnored private let chooseDestination: @MainActor (String, URL, LayoutExportFormat) async -> (URL, LayoutExportFormat)?
    @ObservationIgnored private let revealURL: @MainActor (URL) -> Void
    @ObservationIgnored private let onClose: @MainActor () -> Void
    @ObservationIgnored private let onCancelClose: @MainActor () -> Void
    @ObservationIgnored private let isAvailable: @MainActor (MediaID) -> Bool
    @ObservationIgnored private let defaults: UserDefaults

    /// `sources` lists the options of the left panel; `startSource` is the one to show first.
    /// `fileNames` gives the name of each photo for the captions. `saveDraft` stores the layout (nil clears it).
    /// `isAvailable` is false for a photo that is in the Trash: such a photo stays in the draft, so **Put Back**
    /// keeps its place, but the export leaves it out.
    init(document: LayoutDocument, sources: [LayoutSourceOption], startSource: String, service: LayoutExportService,
         source: URL, protected: @escaping @MainActor () -> ProtectedFiles, fileNames: [MediaID: String],
         saveDraft: @escaping @MainActor (LayoutDocument?) -> Void,
         chooseDestination: @escaping @MainActor (_ name: String, _ folder: URL, _ format: LayoutExportFormat) async -> (URL, LayoutExportFormat)?,
         revealURL: @escaping @MainActor (URL) -> Void,
         onClose: @escaping @MainActor () -> Void,
         onCancelClose: @escaping @MainActor () -> Void = {},
         isAvailable: @escaping @MainActor (MediaID) -> Bool = { _ in true },
         defaults: UserDefaults = .standard) {
        history = History(document)
        pages = LayoutEngine.pages(for: document)
        self.sources = sources
        sourceID = sources.contains { $0.id == startSource } ? startSource : (sources.first?.id ?? startSource)
        self.service = service
        self.source = source
        self.protectedFiles = protected
        self.fileNames = fileNames
        self.saveDraft = saveDraft
        self.chooseDestination = chooseDestination
        self.revealURL = revealURL
        self.onClose = onClose
        self.onCancelClose = onCancelClose
        self.isAvailable = isAvailable
        self.defaults = defaults
        refreshPreview()
    }

    deinit { draftTask?.cancel() }

    // MARK: - State

    var document: LayoutDocument { history.current }
    var canUndo: Bool { history.canUndo || history.hasPendingChange }
    var canRedo: Bool { history.canRedo }
    /// True while a slider or text change waits for its end.
    var hasPendingChange: Bool { history.hasPendingChange }

    var pageText: String { CountText.page(pageIndex + 1, of: pages.count) }
    var countText: String { CountText.photos(document.photoIDs.count) }

    /// "Uses 4 of 6 photos" for a collage, else nil: a contact sheet uses every photo.
    var usedText: String? {
        guard document.kind == .collage else { return nil }
        let count = document.photoIDs.count
        return CountText.uses(min(document.template.cellCount, count), of: count)
    }

    var paperText: String { Self.paperText(document.paper, orientation: document.orientation) }

    /// "A4 (297 × 210 mm)": the name and the size of the paper in the page orientation.
    static func paperText(_ paper: PaperSize, orientation: PageOrientation) -> String {
        let size = paper.millimetres
        let (w, h) = orientation == .portrait ? (size.width, size.height) : (size.height, size.width)
        return String(localized: "\(paperName(paper)) (\(millimetres(w)) × \(millimetres(h)) mm)")
    }

    var spacingText: String { Self.pointsText(document.spacing) }
    var marginText: String { Self.pointsText(document.margin) }

    static func pointsText(_ value: Double) -> String { String(localized: "\(String(Int(value.rounded()))) pt") }

    private static func millimetres(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func paperName(_ paper: PaperSize) -> String {
        switch paper {
        case .a4: "A4"
        case .a3: "A3"
        case .a5: "A5"
        case .letter: "Letter"
        }
    }

    /// The photos of the layout that are in the Trash. The export leaves them out.
    var unavailableCount: Int { document.photoIDs.filter { !isAvailable($0) }.count }

    /// The text of the note after a good export, or nil.
    var savedText: String? { lastExport.isEmpty ? nil : CountText.saved(lastExport.count) }

    // MARK: - Left panel

    var sourceOptions: [LayoutSourceOption] { sources }

    /// The photos of the chosen option that match the search text (case and diacritic insensitive).
    var sourcePhotos: [LayoutPhoto] {
        let photos = sources.first { $0.id == sourceID }?.photos ?? []
        guard let needle = SearchText.needle(searchText) else { return photos }
        return photos.filter { SearchText.matches($0.fileName, needle: needle) }
    }

    /// "N photos" for the photos that the left panel shows.
    var sourceCountText: String { CountText.photos(sourcePhotos.count) }

    /// The photos that the layout holds, for the check mark on the left panel tiles.
    var usedIDs: Set<MediaID> { Set(document.photoIDs) }

    func setSource(_ id: String) {
        guard sources.contains(where: { $0.id == id }) else { return }
        sourceID = id
    }

    /// Gives the captions the new names, for example after a rename.
    func updateFileNames(_ names: [MediaID: String]) {
        fileNames = names
        refreshPreview()
    }

    // MARK: - Settings

    func setKind(_ kind: LayoutKind) { apply { $0.kind = kind } }
    func setPaper(_ paper: PaperSize) { apply { $0.paper = paper } }
    func setOrientation(_ orientation: PageOrientation) { apply { $0.orientation = orientation } }
    func setGrid(_ grid: GridPreset) { apply { $0.grid = grid } }
    func setTemplate(_ template: CollageTemplate) { apply { $0.template = template } }
    func setBackground(_ background: LayoutBackground) { apply { $0.background = background } }
    func setCaptions(_ on: Bool) { apply { $0.showsCaptions = on } }
    func setFileNames(_ on: Bool) { apply { $0.showsFileNames = on } }
    func setResolution(_ resolution: ExportResolution) { apply { $0.resolution = resolution } }

    func setTitle(_ title: String) { slide(.title) { $0.title = title } }
    func setNote(_ note: String) { slide(.note) { $0.note = note } }
    func setSpacing(_ points: Double) { slide(.spacing) { $0.spacing = points } }
    func setMargin(_ points: Double) { slide(.margin) { $0.margin = points } }

    /// The start of a drag of a slider with the mouse: no idle commit until `endDrag`.
    func beginDrag() { pending.beginDrag() }

    /// The end of a drag: all its changes become 1 undo step.
    func endDrag() { pending.endDrag() }

    /// A change that is 1 undo step at once.
    private func apply(_ edit: (inout LayoutDocument) -> Void) {
        finishChange()
        var d = document
        edit(&d)
        history.set(d)
        changed()
    }

    /// A slider or text change: see `PendingCommit`.
    private func slide(_ key: Slider, _ edit: (inout LayoutDocument) -> Void) {
        pending.change(key)
        var d = document
        edit(&d)
        history.show(d)
        changed()
    }

    private func finishChange() { pending.finish() }

    // MARK: - Photos

    func add(_ ids: [MediaID], at index: Int? = nil) {
        var d = document
        guard LayoutService.add(ids, to: &d, at: index) else { return }
        finishChange()
        history.set(d)
        changed()
    }

    func remove(_ ids: [MediaID]) {
        var d = document
        guard LayoutService.remove(ids, from: &d) else { return }
        finishChange()
        history.set(d)
        changed()
    }

    func removeSelected() {
        guard let cell = selectedCell, document.photoIDs.indices.contains(cell) else { return }
        remove([document.photoIDs[cell]])
    }

    func move(_ id: MediaID, to index: Int) {
        var d = document
        guard LayoutService.move(id, to: index, in: &d) else { return }
        finishChange()
        history.set(d)
        changed()
    }

    func swap(_ a: MediaID, _ b: MediaID) {
        var d = document
        guard LayoutService.swap(a, b, in: &d) else { return }
        finishChange()
        history.set(d)
        changed()
    }

    /// Selects a cell, and shows its page. An index with no cell clears the selection.
    func selectCell(_ index: Int?) {
        guard let index, let page = pages.firstIndex(where: { $0.cells.contains { $0.index == index } }) else {
            selectedCell = nil
            return
        }
        selectedCell = index
        if page != pageIndex {
            pageIndex = page
            refreshPreview()
        }
    }

    /// ← and →: selects the cell `offset` places away, across pages. With no selection it selects the first cell of
    /// the shown page. It stays at the first or the last cell.
    func moveSelection(by offset: Int) {
        let total = pages.reduce(0) { $0 + $1.cells.count }
        guard total > 0 else { return }
        guard let current = selectedCell else {
            selectCell(pages[pageIndex].cells.first?.index)
            return
        }
        selectCell(min(max(current + offset, 0), total - 1))
    }

    /// ⌥← and ⌥→: moves the photo of the selected cell `offset` places. The selection follows the photo.
    func moveSelectedPhoto(by offset: Int) {
        guard let cell = selectedCell else { return }
        movePhoto(at: cell, by: offset)
    }

    /// Moves the photo of a cell `offset` places, up to the first or the last photo. A cell with no photo stays.
    func movePhoto(at cell: Int, by offset: Int) {
        let ids = document.photoIDs
        guard ids.indices.contains(cell) else { return }
        let target = min(max(cell + offset, 0), ids.count - 1)
        guard target != cell else { return }
        move(ids[cell], to: target)
        selectCell(target)
    }

    func canMovePhoto(at cell: Int, by offset: Int) -> Bool {
        document.photoIDs.indices.contains(cell) && document.photoIDs.indices.contains(cell + offset)
    }

    func removePhoto(at cell: Int) {
        guard document.photoIDs.indices.contains(cell) else { return }
        remove([document.photoIDs[cell]])
    }

    /// The cell of the shown page under a point, in page points (the view divides a point by `scale`). Nil if none.
    func cell(atPagePoint point: CGPoint) -> Int? {
        pages[pageIndex].cells.first {
            point.x >= $0.frame.x && point.x < $0.frame.maxX && point.y >= $0.frame.y && point.y < $0.frame.maxY
        }?.index
    }

    /// A drop of photos. On a cell they go in at its index. On the page with no cell they go to the end. A photo
    /// that the layout holds already moves instead: onto a cell with a photo it swaps with that photo, onto an
    /// empty cell it goes to the end, and elsewhere nothing changes.
    func drop(_ ids: [MediaID], onCell index: Int?) {
        let held = document.photoIDs
        if ids.count == 1, let id = ids.first, let from = held.firstIndex(of: id) {
            guard let index, index != from else { return }
            if held.indices.contains(index) {
                swap(id, held[index])
                selectCell(index)
            } else {
                move(id, to: held.count - 1)
                selectCell(held.count - 1)
            }
            return
        }
        let before = held.count
        add(ids, at: index)
        if let index, document.photoIDs.count > before { selectCell(min(index, document.photoIDs.count - 1)) }
    }

    /// The text that VoiceOver reads for a cell: "Photo 3 of 6, IMG_2048.jpg" or "Empty cell 4".
    func cellLabel(for cell: LayoutCell) -> String {
        guard let id = cell.mediaID else { return String(localized: "Empty cell \(cell.index + 1)") }
        return String(localized: "Photo \(cell.index + 1) of \(document.photoIDs.count), \(fileNames[id] ?? id)")
    }

    /// True when **Export** has work: not while it runs, and not with no photo.
    var canExport: Bool { !isExporting && !document.photoIDs.isEmpty }

    var currentPage: LayoutPage { pages[pageIndex] }
    var canStepBack: Bool { pageIndex > 0 }
    var canStepForward: Bool { pageIndex < pages.count - 1 }

    // MARK: - Pages and zoom

    /// Shows the page `offset` places away. Does nothing past the first or the last page.
    func step(page offset: Int) {
        let target = pageIndex + offset
        guard pages.indices.contains(target), target != pageIndex else { return }
        pageIndex = target
        refreshPreview()
    }

    /// The scale that makes the whole page fit in the page area, as a fraction of the actual size.
    var fitScale: Double {
        let size = pages[pageIndex].size
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(canvasWidth / size.width, canvasHeight / size.height)
    }

    /// The scale of the page now, as a fraction of the actual size (1 is 100%).
    var scale: Double { fitsPage ? fitScale : chosenScale }

    /// The scale as a percent, for the bottom bar.
    var zoomText: String { "\(Int((scale * 100).rounded()))%" }

    /// Zoom In never makes the page smaller, and Zoom Out never makes it bigger, even at the end of the range.
    func zoomIn() { setScale(scale * Self.zoomStep, direction: 1) }
    func zoomOut() { setScale(scale / Self.zoomStep, direction: -1) }

    func zoomToFit() { fitsPage = true }

    private func setScale(_ value: Double, direction: Double) {
        let now = scale
        let clamped = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        chosenScale = direction > 0 ? max(clamped, now) : min(clamped, now)
        fitsPage = false
    }

    /// **Preview** hides the panels and the cell overlays.
    func togglePreview() { isPreviewing.toggle() }

    /// Esc leaves **Preview** first. Without **Preview** it closes the editor.
    func handleEscape() {
        if isPreviewing { isPreviewing = false } else { requestClose() }
    }

    // MARK: - Undo and closing

    func undo() {
        finishPending()
        history.undo()
        changed()
    }

    func redo() {
        finishPending()
        history.redo()
        changed()
    }

    /// Drops the state of a change that waits for its end, before undo or redo.
    private func finishPending() { pending.drop() }

    /// Saves the draft at once, then closes. There is no discard dialog: the layout is a draft.
    func requestClose() {
        // The save panel and the write still need this editor and its lock (final review C1).
        guard !isExporting else {
            onCancelClose()
            return
        }
        finishChange()
        draftTask?.cancel()
        draftTask = nil
        saveDraft(document)
        onClose()
    }

    // MARK: - After a change

    /// Makes the pages again, drops a selection that has no cell, starts the preview, and plans the draft save.
    private func changed() {
        pages = LayoutEngine.pages(for: document)
        pageIndex = min(pageIndex, pages.count - 1)
        if let cell = selectedCell, !pages.contains(where: { $0.cells.contains { $0.index == cell } }) {
            selectedCell = nil
        }
        refreshPreview()
        scheduleDraft()
    }

    private func scheduleDraft() {
        draftTask?.cancel()
        let delay = draftDelay
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            saveDraft(document)
        }
    }

    /// Starts 1 new render of the shown page. `PreviewChain` cancels the last one, so at most 1 page renders
    /// at a time, and a cancelled render never replaces the image.
    private func refreshPreview() {
        let page = pages[pageIndex], document = document, names = fileNames, source = source, service = service
        let pixels = min(Int((canvasWidth * 2).rounded()), Self.maxPreviewPixel)
        previews.start { [weak self] in
            let image = await service.previewImage(
                of: page, document: document, fileNames: names, maxPixel: max(pixels, 1), source: source)
            guard !Task.isCancelled, let self else { return }
            pageImage = image
        }
    }

    // MARK: - Export

    /// The layout that the export writes: the draft without the photos in the Trash.
    private var exportDocument: LayoutDocument {
        var d = document
        d.photoIDs = d.photoIDs.filter(isAvailable)
        return d
    }

    private var exportFolder: URL {
        let fm = FileManager.default
        if let path = defaults.string(forKey: Self.exportFolderKey) {
            var isFolder: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
        }
        return fm.urls(for: .picturesDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
    }

    /// The suggested file name: the title, or "Layout", with no characters that a file name cannot hold.
    private func suggestedName(format: LayoutExportFormat, in folder: URL) -> String {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let stem = title.isEmpty ? String(localized: "Layout") : title
        return PhotoEditService.uniqueName(stem + "." + format.fileExtension, in: folder)
    }

    /// **Export**: asks for a place with a unique suggested name, then writes the PNG or PDF file.
    /// A photo in the Trash is left out. The layout stays.
    func export(startingWith first: LayoutExportFormat = .pdf) async {
        guard !isExporting else { return }
        finishChange()
        let d = exportDocument
        guard !d.photoIDs.isEmpty else { return }
        // Set before the panel opens, so a second call cannot open a second panel.
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        let folder = exportFolder
        guard let (destination, format) = await chooseDestination(suggestedName(format: first, in: folder), folder, first)
        else { return }
        lastExport = []
        do {
            lastExport = try await service.export(
                d, fileNames: fileNames, source: source, to: destination, format: format, protected: protectedFiles())
            defaults.set(destination.deletingLastPathComponent().path, forKey: Self.exportFolderKey)
        } catch is CancellationError {
            return
        } catch {
            exportError = CoreErrorMessages.text(for: error)
        }
    }

    func revealLastExport() {
        guard let first = lastExport.first else { return }
        revealURL(first)
    }
}
