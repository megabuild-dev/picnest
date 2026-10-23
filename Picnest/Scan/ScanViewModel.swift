import Foundation
import Observation
import PicnestCore

/// Estimates the time left from the mean seconds per photo over the last 64 photos.
struct ETAEstimator {
    static let window = 64
    private var samples: [(time: Date, done: Int)] = []
    private var total = 0
    private var count = 0

    mutating func add(done: Int, total: Int, at time: Date) {
        samples.append((time, done))
        self.total = total
        count += 1
        // Keep the newest sample at or below the window edge as the anchor, and everything after it.
        if let anchor = samples.lastIndex(where: { $0.done <= done - Self.window }), anchor > 0 {
            samples.removeFirst(anchor)
        }
    }

    /// "About N minutes left", "Less than a minute left", or nil until 2 events with progress.
    var text: String? {
        guard count >= 2, let first = samples.first, let last = samples.last,
              last.done > first.done else { return nil }
        let perPhoto = last.time.timeIntervalSince(first.time) / Double(last.done - first.done)
        let seconds = perPhoto * Double(max(total - last.done, 0))
        if seconds <= 60 { return "Less than a minute left" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes == 1 ? "About 1 minute left" : "About \(minutes.formatted()) minutes left"
    }
}

/// State of the Scan screen (spec 3.2). Talks to `ScanService` and `AppModel` only.
@MainActor
@Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case preparingModel
        case embedding(done: Int, total: Int)
        /// The scan found no photos.
        case empty
        /// macOS denied access to the folder (spec 12, risk 4).
        case permissionDenied
        case failed(String)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    private(set) var phase: Phase = .preparingModel
    private(set) var etaText: String?
    /// Every phase the scan went through, in order. For tests.
    private(set) var history: [Phase] = [.preparingModel]

    let source: URL
    /// The session to scan again, or nil for a first scan.
    @ObservationIgnored private let rescanOf: Session?
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let scanService: ScanService
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var estimator = ETAEstimator()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The token of `AppModel.beginScan` while this scan runs.
    @ObservationIgnored private var scanToken: UUID?

    init(
        app: AppModel, scanService: ScanService, source: URL, rescanOf: Session? = nil,
        openURL: @escaping (URL) -> Void, now: @escaping () -> Date = Date.init, locale: Locale = .current
    ) {
        self.app = app
        self.scanService = scanService
        self.source = source
        self.rescanOf = rescanOf
        self.openURL = openURL
        self.now = now
        self.locale = locale
    }

    var folderName: String { source.lastPathComponent }

    /// Text above the bar for the running phases, or the message of an end state.
    var message: String {
        switch phase {
        case .preparingModel: "Preparing the model…"
        case .embedding: "Looking at your photos…"
        case .empty: "No photos found in this folder."
        case .permissionDenied: "Picnest cannot open this folder."
        case .failed(let text): text
        }
    }

    /// The count under the bar, for example `1,240 / 2,413`. Nil outside the embedding phase.
    var countText: String? {
        guard case .embedding(let done, let total) = phase else { return nil }
        return Self.countText(done: done, total: total, locale: locale)
    }

    /// 0...1 for the bar, or nil while the bar has no known length.
    var fraction: Double? {
        guard case .embedding(let done, let total) = phase, total > 0 else { return nil }
        return Double(done) / Double(total)
    }

    var isRunning: Bool {
        switch phase {
        case .preparingModel, .embedding: true
        default: false
        }
    }

    static func countText(done: Int, total: Int, locale: Locale) -> String {
        "\(done.formatted(.number.locale(locale))) / \(total.formatted(.number.locale(locale)))"
    }

    /// Starts the scan: a rescan of `rescanOf` (spec 5.1), or a first scan that names categories from
    /// **All topics** (spec 4.3). Does nothing if it already started, or if a scan of the folder already runs.
    func start() {
        guard task == nil, let token = app.beginScan(source) else { return }
        scanToken = token
        let app = self.app
        let stream = if let rescanOf {
            scanService.rescan(rescanOf, source: source)
        } else {
            scanService.firstScan(source: source)
        }
        task = Task { [weak self] in
            defer { app.endScan(token) }
            do {
                for try await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    handle(event)
                }
            } catch is CancellationError {
                return  // Only `cancel()` navigates.
            } catch {
                guard let self, !Task.isCancelled else { return }
                set(Self.isPermissionError(error) ? .permissionDenied : .failed(Self.readable(error)))
            }
        }
    }

    /// Stops the scan, keeps the embeddings that exist, and goes back to Welcome.
    func cancel() {
        stop()
        app.showWelcome()
    }

    /// Stops the scan without navigation. The view calls it when it leaves the window.
    func stop() {
        task?.cancel()
        if let scanToken { app.endScan(scanToken) }
    }

    func back() { app.showWelcome() }

    func chooseAnotherFolder() { app.showWelcome() }

    func openSystemSettings() { openURL(Self.settingsURL) }

    /// Waits until the scan task ends. For tests.
    func settled() async {
        await task?.value
    }

    // MARK: - Private

    private func handle(_ event: ScanEvent) {
        switch event {
        case .preparingModel:
            set(.preparingModel)
        case .embedding(let done, let total):
            estimator.add(done: done, total: total, at: now())
            etaText = estimator.text
            set(.embedding(done: done, total: total))
        case .finished(let session):
            if session.scan.media.isEmpty {
                set(.empty)
            } else {
                app.finishScan(session)
            }
        }
    }

    private func set(_ new: Phase) {
        phase = new
        if history.last != new { history.append(new) }
    }

    static func isPermissionError(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.fileReadNoPermission.rawValue { return true }
        let posix = ns.domain == NSPOSIXErrorDomain ? ns : ns.userInfo[NSUnderlyingErrorKey] as? NSError
        if let posix, posix.domain == NSPOSIXErrorDomain, posix.code == Int(EACCES) || posix.code == Int(EPERM) {
            return true
        }
        return false
    }

    private static func readable(_ error: any Error) -> String {
        "The scan failed. \(error.localizedDescription)"
    }
}
