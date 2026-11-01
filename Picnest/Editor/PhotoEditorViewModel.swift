import CoreGraphics
import Foundation
import Observation
import PicnestCore

/// A photo that the editor can open: its id in the session, its file, and its file name.
struct EditorPhoto: Identifiable, Hashable {
    let id: MediaID
    let url: URL
    let fileName: String
}

/// The 4 tools of the left rail.
enum EditorTool: CaseIterable {
    case crop, straighten, rotate, adjust
}

/// The state and the actions of the photo editor (UI redesign, Phase 4). It holds the edit of the shown photo
/// with its undo history, the preview, and the export. The edit applies to 1 photo at a time: a change of photo
/// starts a new history, and asks first when the edit has changes. The original file is never changed.
@MainActor @Observable
final class PhotoEditorViewModel {
    /// The action that waits for **Discard Edits**.
    private enum Pending {
        case show(MediaID)
        case close
    }

    var tool: EditorTool = .crop {
        didSet { if tool != oldValue { refreshPreview() } }
    }
    /// While true, the preview is the photo with no edit.
    var isShowingOriginal = false {
        didSet { if isShowingOriginal != oldValue { refreshPreview() } }
    }
    /// The preview of the edit: the whole frame with the **Crop** tool, else the cropped result.
    private(set) var previewImage: CGImage?
    private(set) var isExporting = false
    /// The text of the last failed export, or nil.
    var exportError: String?
    /// The copy that the last export wrote for the shown photo, or nil.
    private(set) var lastExport: URL?
    /// True while the Discard Edits dialog shows.
    var isConfirmingDiscard = false

    private var history = EditHistory()
    private var index: Int
    /// The preview of the shown photo with no edit, and the id it belongs to.
    private var base: (id: MediaID, image: CGImage)?

    @ObservationIgnored private let photos: [EditorPhoto]
    @ObservationIgnored private let service: PhotoEditService
    @ObservationIgnored private let protected: ProtectedFiles
    @ObservationIgnored private let chooseDestination: @MainActor (String, URL, ExportFormat) async -> (URL, ExportFormat)?
    @ObservationIgnored private let revealURL: @MainActor (URL) -> Void
    @ObservationIgnored private let onClose: @MainActor () -> Void
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored nonisolated(unsafe) private var previewTask: Task<Void, Never>?

    /// `photos` must not be empty. `start` is the photo to show first (the first one if it is not in `photos`).
    /// `chooseDestination` shows the save panel with a suggested name, a folder, and a format; it returns the
    /// chosen file and format, or nil on cancel.
    init(photos: [EditorPhoto], start: MediaID, service: PhotoEditService, protected: ProtectedFiles,
         chooseDestination: @escaping @MainActor (_ suggestedName: String, _ folder: URL, _ format: ExportFormat) async -> (URL, ExportFormat)?,
         revealURL: @escaping @MainActor (URL) -> Void,
         onClose: @escaping @MainActor () -> Void) {
        precondition(!photos.isEmpty, "The editor needs at least 1 photo.")
        self.photos = photos
        index = photos.firstIndex { $0.id == start } ?? 0
        self.service = service
        self.protected = protected
        self.chooseDestination = chooseDestination
        self.revealURL = revealURL
        self.onClose = onClose
        refreshPreview()
    }

    deinit { previewTask?.cancel() }

    // MARK: - State

    var edit: PhotoEdit { history.current }
    var current: EditorPhoto { photos[index] }
    var allPhotos: [EditorPhoto] { photos }
    var positionText: String { String(localized: "\(index + 1) of \(photos.count)") }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var hasChanges: Bool { !edit.isOriginal }

    /// The size of the whole frame after the quarter turns, in pixels of the preview. Nil until the preview loads.
    private var frame: (size: PixelSize, original: PixelSize)? {
        guard let image = base?.image else { return nil }
        let original = PixelSize(width: image.width, height: image.height)
        return (PhotoEditService.frameSize(of: edit, source: original), original)
    }

    private var frameAspect: Double {
        guard let size = frame?.size, size.height > 0 else { return 1 }
        return Double(size.width) / Double(size.height)
    }

    private var cropRatio: Double? {
        guard let frame else { return nil }
        return edit.aspect.ratio(frame: frame.size, original: frame.original)
    }

    // MARK: - Edits

    func rotate(clockwise: Bool) {
        var e = edit
        e.rotate(clockwise: clockwise)
        change(e, commit: true)
    }

    func flip(horizontal: Bool) {
        var e = edit
        e.flip(horizontal: horizontal)
        change(e, commit: true)
    }

    func setAspect(_ aspect: AspectRatio) {
        var e = edit
        e.aspect = aspect
        if let frame, let ratio = aspect.ratio(frame: frame.size, original: frame.original) {
            e.crop = CropGeometry.fit(e.crop, ratio: ratio, frameAspect: frameAspect)
        }
        change(e, commit: true)
    }

    /// Moves a crop handle by `dx` and `dy`, in 0…1 units of the frame, from where the crop is now.
    /// The change is 1 undo step after `endDrag`.
    func dragCrop(_ handle: CropHandle, dx: Double, dy: Double) {
        var e = edit
        e.crop = CropGeometry.drag(e.crop, handle: handle, dx: dx, dy: dy, ratio: cropRatio, frameAspect: frameAspect)
        change(e, commit: false)
    }

    func setStraighten(_ degrees: Double) {
        var e = edit
        e.straighten = degrees
        change(e, commit: false)
    }

    func setAdjustment(_ kind: AdjustmentKind, _ value: Int) {
        var e = edit
        e[kind] = value
        change(e, commit: false)
    }

    /// The end of a drag of a handle or a slider: all its changes become 1 undo step.
    func endDrag() {
        history.commit()
    }

    func reset() {
        history.reset()
        refreshPreview()
    }

    func undo() {
        history.undo()
        refreshPreview()
    }

    func redo() {
        history.redo()
        refreshPreview()
    }

    private func change(_ e: PhotoEdit, commit: Bool) {
        history.show(e)
        if commit { history.commit() }
        refreshPreview()
    }

    // MARK: - Photos and closing

    /// Shows the photo `offset` places away. Does nothing past the first or the last photo.
    func step(by offset: Int) {
        let target = index + offset
        guard photos.indices.contains(target) else { return }
        move(to: photos[target].id)
    }

    func select(_ id: MediaID) {
        guard id != current.id, photos.contains(where: { $0.id == id }) else { return }
        move(to: id)
    }

    func requestClose() {
        if hasChanges {
            ask(.close)
        } else {
            onClose()
        }
    }

    /// **Discard Edits**: does the action that waited for it.
    func confirmDiscard() {
        isConfirmingDiscard = false
        guard let action = pending else { return }
        pending = nil
        switch action {
        case .show(let id): show(id)
        case .close: onClose()
        }
    }

    private func move(to id: MediaID) {
        if hasChanges {
            ask(.show(id))
        } else {
            show(id)
        }
    }

    private func ask(_ action: Pending) {
        pending = action
        isConfirmingDiscard = true
    }

    private func show(_ id: MediaID) {
        guard let target = photos.firstIndex(where: { $0.id == id }) else { return }
        index = target
        history = EditHistory()
        base = nil
        previewImage = nil
        lastExport = nil
        exportError = nil
        refreshPreview()
    }

    // MARK: - Preview

    /// Cancels the last preview task and starts 1 new task. The task decodes the base preview once per photo,
    /// then applies the edit off the main actor.
    private func refreshPreview() {
        previewTask?.cancel()
        let photo = current, edit = edit, service = service
        let cropping = tool != .crop, plain = isShowingOriginal || edit.isOriginal
        let known = base?.id == photo.id ? base?.image : nil
        previewTask = Task { [weak self] in
            var source = known
            if source == nil {
                source = await service.preview(at: photo.url)
                guard !Task.isCancelled, let self, current.id == photo.id else { return }
                if let image = source { base = (photo.id, image) }
            }
            guard let source else { return }
            let result: CGImage? = plain
                ? source
                : await Task.detached(priority: .userInitiated) { service.apply(edit, to: source, cropping: cropping) }.value
            guard !Task.isCancelled, let self, current.id == photo.id else { return }
            previewImage = result
        }
    }

    // MARK: - Export

    /// The text of the note after a good export, or nil.
    var savedText: String? {
        lastExport.map { String(localized: "Saved “\($0.lastPathComponent)”.") }
    }

    /// **Export edited copy**: asks for a place with a unique suggested name, then writes the copy. The edit stays.
    func export() async {
        guard !isExporting else { return }
        let photo = current, edit = edit
        let folder = photo.url.deletingLastPathComponent()
        let format = ExportFormat.defaultFormat(forExtension: photo.url.pathExtension)
        let stem = (photo.fileName as NSString).deletingPathExtension
        let suggested = PhotoEditService.uniqueName(
            String(localized: "\(stem) edited") + "." + format.fileExtension, in: folder)
        guard let (destination, chosen) = await chooseDestination(suggested, folder, format) else { return }
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let written = try await service.exportCopy(
                of: photo.url, edit: edit, to: destination, format: chosen, protected: protected)
            if current.id == photo.id { lastExport = written }
        } catch is CancellationError {
            return
        } catch {
            exportError = CoreErrorMessages.text(for: error)
        }
    }

    func revealLastExport() {
        guard let lastExport else { return }
        revealURL(lastExport)
    }
}
