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
    /// The scale of the page. 1 is 100%. `fitsPage` is true until the user zooms.
    private(set) var zoom: Double = 1
    private(set) var fitsPage = true
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

    private var history: History<LayoutDocument>
    private var pendingSlider: Slider?
    private var isDragging = false
    @ObservationIgnored nonisolated(unsafe) private var idleCommit: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var draftTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var previewTask: Task<Void, Never>?
    /// How long a slider or text change that has no end event waits for the next one before it is 1 undo step.
    @ObservationIgnored var commitDelay: Duration = .milliseconds(600)
    /// How long the draft waits after a change before it saves. A test hook.
    @ObservationIgnored var draftDelay: Duration = .seconds(1)

    @ObservationIgnored private let sources: [LayoutSourceOption]
    @ObservationIgnored private let service: LayoutExportService
    @ObservationIgnored private let source: URL
    @ObservationIgnored private let protected: ProtectedFiles
    @ObservationIgnored private var fileNames: [MediaID: String]
    @ObservationIgnored private let saveDraft: @MainActor (LayoutDocument?) -> Void
    @ObservationIgnored private let chooseDestination: @MainActor (String, URL, LayoutExportFormat) async -> (URL, LayoutExportFormat)?
    @ObservationIgnored private let revealURL: @MainActor (URL) -> Void
    @ObservationIgnored private let onClose: @MainActor () -> Void
    @ObservationIgnored private let isAvailable: @MainActor (MediaID) -> Bool
    @ObservationIgnored private let defaults: UserDefaults

    /// `sources` lists the options of the left panel; `startSource` is the one to show first.
    /// `fileNames` gives the name of each photo for the captions. `saveDraft` stores the layout (nil clears it).
    /// `isAvailable` is false for a photo that is in the Trash: such a photo stays in the draft, so **Put Back**
    /// keeps its place, but the export leaves it out.
    init(document: LayoutDocument, sources: [LayoutSourceOption], startSource: String, service: LayoutExportService,
         source: URL, protected: ProtectedFiles, fileNames: [MediaID: String],
         saveDraft: @escaping @MainActor (LayoutDocument?) -> Void,
         chooseDestination: @escaping @MainActor (_ name: String, _ folder: URL, _ format: LayoutExportFormat) async -> (URL, LayoutExportFormat)?,
         revealURL: @escaping @MainActor (URL) -> Void,
         onClose: @escaping @MainActor () -> Void,
         isAvailable: @escaping @MainActor (MediaID) -> Bool = { _ in true },
         defaults: UserDefaults = .standard) {
        history = History(document)
        pages = LayoutEngine.pages(for: document)
        self.sources = sources
        sourceID = sources.contains { $0.id == startSource } ? startSource : (sources.first?.id ?? startSource)
        self.service = service
        self.source = source
        self.protected = protected
        self.fileNames = fileNames
        self.saveDraft = saveDraft
        self.chooseDestination = chooseDestination
        self.revealURL = revealURL
        self.onClose = onClose
        self.isAvailable = isAvailable
        self.defaults = defaults
        refreshPreview()
    }

    deinit { idleCommit?.cancel(); draftTask?.cancel(); previewTask?.cancel() }

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

    var paperText: String {
        let size = document.paper.millimetres
        let (w, h) = document.orientation == .portrait ? (size.width, size.height) : (size.height, size.width)
        return String(localized: "\(Self.paperName(document.paper)) (\(Self.millimetres(w)) × \(Self.millimetres(h)) mm)")
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
        guard let needle = ReviewViewModel.searchNeedle(searchText) else { return photos }
        return photos.filter { ReviewViewModel.fold($0.fileName).contains(needle) }
    }

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
    func beginDrag() {
        isDragging = true
        idleCommit?.cancel()
    }

    /// The end of a drag: all its changes become 1 undo step.
    func endDrag() {
        isDragging = false
        finishChange()
    }

    /// A change that is 1 undo step at once.
    private func apply(_ edit: (inout LayoutDocument) -> Void) {
        finishChange()
        var d = document
        edit(&d)
        history.set(d)
        changed()
    }

    /// A slider or text change. A mouse drag ends with `endDrag`. A key or VoiceOver change has no end event, so
    /// it becomes 1 undo step after `commitDelay` with no new change, or when another field changes.
    private func slide(_ key: Slider, _ edit: (inout LayoutDocument) -> Void) {
        if let pendingSlider, pendingSlider != key { history.commit() }
        pendingSlider = key
        var d = document
        edit(&d)
        history.show(d)
        changed()
        idleCommit?.cancel()
        guard !isDragging else { return }
        let delay = commitDelay
        idleCommit = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finishChange()
        }
    }

    private func finishChange() {
        idleCommit?.cancel()
        idleCommit = nil
        pendingSlider = nil
        history.commit()
    }

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

    func selectCell(_ index: Int?) { selectedCell = index }

    // MARK: - Pages and zoom

    /// Shows the page `offset` places away. Does nothing past the first or the last page.
    func step(page offset: Int) {
        let target = pageIndex + offset
        guard pages.indices.contains(target), target != pageIndex else { return }
        pageIndex = target
        refreshPreview()
    }

    func zoomIn() { setZoom(zoom * Self.zoomStep) }
    func zoomOut() { setZoom(zoom / Self.zoomStep) }

    func zoomToFit() {
        fitsPage = true
        zoom = 1
    }

    private func setZoom(_ value: Double) {
        fitsPage = false
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// **Preview** hides the panels and the cell overlays.
    func togglePreview() { isPreviewing.toggle() }

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
    private func finishPending() {
        idleCommit?.cancel()
        idleCommit = nil
        pendingSlider = nil
    }

    /// Saves the draft at once, then closes. There is no discard dialog: the layout is a draft.
    func requestClose() {
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

    /// Cancels the last preview task and starts 1 new task. The new task waits for the old one, so at most 1
    /// page renders at a time, and a cancelled task skips its render.
    private func refreshPreview() {
        let previous = previewTask
        previous?.cancel()
        let page = pages[pageIndex], document = document, names = fileNames, source = source, service = service
        let pixels = min(Int((canvasWidth * 2).rounded()), Self.maxPreviewPixel)
        previewTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
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
    func export() async {
        guard !isExporting else { return }
        finishChange()
        let d = exportDocument
        guard !d.photoIDs.isEmpty else { return }
        let folder = exportFolder
        guard let (destination, format) = await chooseDestination(suggestedName(format: .pdf, in: folder), folder, .pdf)
        else { return }
        isExporting = true
        exportError = nil
        lastExport = []
        defer { isExporting = false }
        do {
            lastExport = try await service.export(
                d, fileNames: fileNames, source: source, to: destination, format: format, protected: protected)
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
