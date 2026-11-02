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
final class PhotoEditorViewModel: EditorSession {
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

    private enum Slider: Equatable {
        case straighten
        case adjustment(AdjustmentKind)
    }

    private var history = EditHistory()
    private var pendingSlider: Slider?
    private var dragStartCrop: NormalizedRect?
    private var isDragging = false
    @ObservationIgnored nonisolated(unsafe) private var idleCommit: Task<Void, Never>?
    /// How long a slider change that has no end event waits for the next one before it is 1 undo step.
    @ObservationIgnored var commitDelay: Duration = .milliseconds(600)
    private var index: Int
    /// The preview of the shown photo with no edit, and the id it belongs to.
    private var base: (id: MediaID, image: CGImage)?
    /// The pixel size of the shown file as stored, before its EXIF turn, and the id it belongs to.
    private var storedSize: (id: MediaID, size: PixelSize)?

    @ObservationIgnored private let photos: [EditorPhoto]
    @ObservationIgnored private let service: PhotoEditService
    @ObservationIgnored private let protected: ProtectedFiles
    @ObservationIgnored private let chooseDestination: @MainActor (String, URL, ExportFormat) async -> (URL, ExportFormat)?
    @ObservationIgnored private let revealURL: @MainActor (URL) -> Void
    @ObservationIgnored private let onClose: @MainActor () -> Void
    @ObservationIgnored private let onCancelClose: @MainActor () -> Void
    @ObservationIgnored private let readSize: @MainActor (MediaID) async -> PixelSize?
    /// The decode of the base preview of the shown photo. An edit never restarts it.
    @ObservationIgnored private var baseTask: (id: MediaID, task: Task<CGImage?, Never>)?
    /// True when `setAspect` ran before the base preview loaded, so the crop still needs to fit.
    @ObservationIgnored private var needsFit = false
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored nonisolated(unsafe) private var previewTask: Task<Void, Never>?

    /// `photos` must not be empty. `start` is the photo to show first (the first one if it is not in `photos`).
    /// `chooseDestination` shows the save panel with a suggested name, a folder, and a format; it returns the
    /// chosen file and format, or nil on cancel.
    init(photos: [EditorPhoto], start: MediaID, service: PhotoEditService, protected: ProtectedFiles,
         chooseDestination: @escaping @MainActor (_ suggestedName: String, _ folder: URL, _ format: ExportFormat) async -> (URL, ExportFormat)?,
         revealURL: @escaping @MainActor (URL) -> Void,
         onClose: @escaping @MainActor () -> Void,
         onCancelClose: @escaping @MainActor () -> Void = {},
         readSize: @escaping @MainActor (MediaID) async -> PixelSize? = { _ in nil }) {
        precondition(!photos.isEmpty, "The editor needs at least 1 photo.")
        self.photos = photos
        index = photos.firstIndex { $0.id == start } ?? 0
        self.service = service
        self.protected = protected
        self.chooseDestination = chooseDestination
        self.revealURL = revealURL
        self.onClose = onClose
        self.onCancelClose = onCancelClose
        self.readSize = readSize
        refreshPreview()
        loadStoredSize()
    }

    deinit { previewTask?.cancel(); idleCommit?.cancel() }

    // MARK: - State

    var edit: PhotoEdit { history.current }
    var current: EditorPhoto { photos[index] }
    var allPhotos: [EditorPhoto] { photos }
    var positionText: String { String(localized: "\(index + 1) of \(photos.count)") }
    var canUndo: Bool { history.canUndo || history.hasPendingChange }
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
        if let frame {
            if let ratio = aspect.ratio(frame: frame.size, original: frame.original) {
                e.crop = CropGeometry.fit(e.crop, ratio: ratio, frameAspect: frameAspect)
            }
            change(e, commit: true)
        } else if aspect == .freeform {
            change(e, commit: true)  // no ratio, so nothing to fit
        } else {
            // The frame is not known yet. Show the aspect now; the crop fits and the step commits on load.
            needsFit = true
            change(e, commit: false)
        }
    }

    /// Moves a crop handle. `dx` and `dy` are the whole translation since the drag started, in 0…1 units of the
    /// frame, so a drag back after a clamp at an edge follows the pointer. The change is 1 undo step after `endDrag`.
    func dragCrop(_ handle: CropHandle, dx: Double, dy: Double) {
        let start = dragStartCrop ?? edit.crop
        dragStartCrop = start
        var e = edit
        e.crop = CropGeometry.drag(start, handle: handle, dx: dx, dy: dy, ratio: cropRatio, frameAspect: frameAspect)
        change(e, commit: false)
    }

    func setStraighten(_ degrees: Double) {
        var e = edit
        e.straighten = degrees
        slide(.straighten, e)
    }

    func setAdjustment(_ kind: AdjustmentKind, _ value: Int) {
        var e = edit
        e[kind] = value
        slide(.adjustment(kind), e)
    }

    /// A slider changed. A mouse drag ends with `endDrag`. A key or VoiceOver change has no end event, so it
    /// becomes 1 undo step after `commitDelay` with no new change, or when another slider changes.
    private func slide(_ key: Slider, _ e: PhotoEdit) {
        if let pendingSlider, pendingSlider != key { history.commit() }
        pendingSlider = key
        change(e, commit: false)
        idleCommit?.cancel()
        guard !isDragging else { return }
        let delay = commitDelay
        idleCommit = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finishChange()
        }
    }

    /// The start of a drag of a slider with the mouse: no idle commit until `endDrag`.
    func beginDrag() {
        isDragging = true
        idleCommit?.cancel()
    }

    /// The end of a drag of a handle or a slider: all its changes become 1 undo step.
    func endDrag() {
        isDragging = false
        finishChange()
    }

    private func finishChange() {
        idleCommit?.cancel()
        idleCommit = nil
        pendingSlider = nil
        dragStartCrop = nil
        history.commit()
    }

    func reset() {
        finishPending()
        history.reset()
        refreshPreview()
    }

    func undo() {
        finishPending()
        history.undo()
        refreshPreview()
    }

    func redo() {
        finishPending()
        history.redo()
        refreshPreview()
    }

    /// Drops the state of a drag or a slider change that waits for its end, before undo, redo, or reset.
    /// The history itself drops or keeps the shown value.
    private func finishPending() {
        idleCommit?.cancel()
        idleCommit = nil
        pendingSlider = nil
        dragStartCrop = nil
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

    /// **Cancel** in the Discard Edits dialog: the waiting action is dropped.
    func cancelDiscard() {
        pending = nil
        isConfirmingDiscard = false
        onCancelClose()
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
        finishPending()
        history = EditHistory()
        base = nil
        baseTask = nil
        needsFit = false
        previewImage = nil
        lastExport = nil
        exportError = nil
        storedSize = nil
        refreshPreview()
        loadStoredSize()
    }

    private func loadStoredSize() {
        let id = current.id, readSize = readSize
        Task { [weak self] in
            guard let size = await readSize(id), let self, current.id == id else { return }
            storedSize = (id, size)
        }
    }

    // MARK: - Screen state (decided here, so the views stay plain)

    /// The size of the file in upright pixels. The stored size turns when the preview has the other orientation.
    private var uprightSize: PixelSize? {
        guard let stored = storedSize, stored.id == current.id else { return nil }
        let size = stored.size
        guard let image = base?.image, image.width != image.height, size.width != size.height else { return size }
        let previewIsLandscape = image.width > image.height
        return (size.width > size.height) == previewIsLandscape ? size : PixelSize(width: size.height, height: size.width)
    }

    /// The size of the exported copy, for example "4032 × 3024". Empty while the file size is unknown.
    var outputSizeText: String {
        guard let source = uprightSize else { return "" }
        let size = PhotoEditService.outputSize(of: edit, source: source)
        return "\(size.width.formatted(.number.grouping(.never))) × \(size.height.formatted(.number.grouping(.never)))"
    }

    /// The line under the canvas: the file name, then "Original" or "Edited".
    var statusText: String {
        hasChanges
            ? String(localized: "\(current.fileName) · Edited")
            : String(localized: "\(current.fileName) · Original")
    }

    /// The count line of the filmstrip.
    var setCountText: String { CountText.inSet(photos.count) }

    /// The canvas draws the shade, the crop frame, and the handles only with the **Crop** tool.
    var showsCropFrame: Bool { tool == .crop && !isShowingOriginal }
    /// The 3 × 3 grid shows with **Crop** and **Straighten**.
    var showsGrid: Bool { (tool == .crop || tool == .straighten) && !isShowingOriginal }
    var canStepBack: Bool { index > 0 }
    var canStepForward: Bool { index < photos.count - 1 }

    /// The text of a slider value, for example "+20", "-5", or "0".
    static func adjustmentText(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    /// The text of the straighten angle, for example "+10.5°".
    static func straightenText(_ degrees: Double, locale: Locale = .current) -> String {
        let rounded = (degrees * 10).rounded() / 10
        let body = rounded.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return (rounded > 0 ? "+" : "") + body + "°"
    }

    /// Makes the crop frame `factor` times as large around its center, inside the frame. 1 undo step.
    /// A locked ratio stays. The frame never gets under 5% of a side.
    func scaleCrop(by factor: Double) {
        let c = edit.crop
        var w = min(c.width * factor, 1), h = min(c.height * factor, 1)
        if cropRatio != nil {
            let k = c.height / c.width
            let scale = min(w / c.width, h / c.height)
            w = c.width * scale
            h = w * k
        }
        guard w >= 0.05, h >= 0.05 else { return }
        var e = edit
        e.crop = NormalizedRect(
            x: min(max(c.x + c.width / 2 - w / 2, 0), 1 - w), y: min(max(c.y + c.height / 2 - h / 2, 0), 1 - h),
            width: w, height: h)
        change(e, commit: true)
    }

    // MARK: - Preview

    /// Cancels the last preview task and starts 1 new task. The new task waits for the old one, so at most 1
    /// edit renders at a time, and a cancelled task skips its render. The base preview decodes once per photo,
    /// in its own task that an edit does not cancel. The render runs off the main actor.
    private func refreshPreview() {
        let previous = previewTask
        previous?.cancel()
        let photo = current, edit = edit, service = service
        let showCropped = tool != .crop, plain = isShowingOriginal || edit.isOriginal
        let decode = baseDecode(for: photo)
        previewTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            guard let source = await decode.value else { return }
            guard !Task.isCancelled, let self, current.id == photo.id else { return }
            if base?.id != photo.id {
                base = (photo.id, source)
                fitCropIfNeeded()
            }
            // `fitCropIfNeeded` may have changed the edit; the next refresh draws it.
            let drawn = self.edit
            let result: CGImage? = plain && drawn == edit
                ? source
                : await Task.detached(priority: .userInitiated) {
                    service.apply(drawn, to: source, cropping: showCropped)
                }.value
            guard !Task.isCancelled, current.id == photo.id else { return }
            previewImage = result
        }
    }

    private func baseDecode(for photo: EditorPhoto) -> Task<CGImage?, Never> {
        if let baseTask, baseTask.id == photo.id { return baseTask.task }
        let service = service
        let task = Task { await service.preview(at: photo.url) }
        baseTask = (photo.id, task)
        return task
    }

    /// After the base loads: fits the crop to an aspect that was set before, as part of the same undo step.
    private func fitCropIfNeeded() {
        guard needsFit else { return }
        needsFit = false
        var e = edit
        if let frame, let ratio = e.aspect.ratio(frame: frame.size, original: frame.original) {
            e.crop = CropGeometry.fit(e.crop, ratio: ratio, frameAspect: frameAspect)
        }
        history.show(e)
        history.commit()
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
