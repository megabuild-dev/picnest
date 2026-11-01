import Foundation
import UniformTypeIdentifiers

/// An adjustment slider of the photo editor. Each one reads -100…100.
public enum AdjustmentKind: String, CaseIterable, Sendable {
    case exposure, contrast, warmth, saturation
}

/// A rectangle in 0…1 units of the frame. The origin is the top left.
public struct NormalizedRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

public enum AspectRatio: String, CaseIterable, Sendable, Hashable {
    case original, freeform, square, fourThree, threeTwo, sixteenNine

    /// Width ÷ height in pixels, or `nil` for `freeform`. A fixed ratio follows
    /// the orientation of `frame`: a portrait frame gives 3:4, not 4:3.
    public func ratio(frame: PixelSize, original: PixelSize) -> Double? {
        let landscape = frame.width >= frame.height
        func oriented(_ a: Double, _ b: Double) -> Double {
            let long = max(a, b), short = min(a, b)
            return landscape ? long / short : short / long
        }
        switch self {
        case .freeform: return nil
        case .square: return 1
        case .original: return oriented(Double(original.width), Double(original.height))
        case .fourThree: return oriented(4, 3)
        case .threeTwo: return oriented(3, 2)
        case .sixteenNine: return oriented(16, 9)
        }
    }
}

/// The edit recipe of one photo. The flips apply after the quarter turns,
/// in the frame the user sees. `crop` is in that same frame.
public struct PhotoEdit: Sendable, Hashable {
    public var straighten: Double = 0 {
        didSet { straighten = min(max(straighten, -45), 45) }
    }
    public var quarterTurns: Int = 0 {
        didSet { quarterTurns = ((quarterTurns % 4) + 4) % 4 }
    }
    public var flipHorizontal = false
    public var flipVertical = false
    public var crop: NormalizedRect = .full
    public var aspect: AspectRatio = .original
    private var adjustments: [AdjustmentKind: Int] = [:]

    public init() {}

    public static let original = PhotoEdit()

    public var isOriginal: Bool { self == .original }

    public subscript(_ kind: AdjustmentKind) -> Int {
        get { adjustments[kind] ?? 0 }
        set {
            let v = min(max(newValue, -100), 100)
            adjustments[kind] = v == 0 ? nil : v
        }
    }

    public mutating func rotate(clockwise: Bool) {
        let c = crop
        if clockwise {
            crop = NormalizedRect(x: 1 - c.y - c.height, y: c.x, width: c.height, height: c.width)
            quarterTurns += 1
        } else {
            crop = NormalizedRect(x: c.y, y: 1 - c.x - c.width, width: c.height, height: c.width)
            quarterTurns += 3
        }
    }

    public mutating func flip(horizontal: Bool) {
        if horizontal {
            flipHorizontal.toggle()
            crop.x = 1 - crop.x - crop.width
        } else {
            flipVertical.toggle()
            crop.y = 1 - crop.y - crop.height
        }
    }
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case jpeg, heic, png

    public var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .png: return .png
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        }
    }

    /// The format that suits the original file. WebP cannot be written, so it goes to JPEG.
    public static func defaultFormat(forExtension ext: String) -> ExportFormat {
        switch ext.lowercased() {
        case "heic", "heif": return .heic
        case "png", "tiff", "tif", "gif": return .png
        default: return .jpeg
        }
    }
}

/// Undo and redo for a `PhotoEdit`. `show` changes `current` with no step,
/// so a drag can show many values and `commit` them as 1 step.
public struct EditHistory: Sendable {
    public private(set) var current: PhotoEdit = .original
    private var committed: PhotoEdit = .original
    private var past: [PhotoEdit] = []
    private var future: [PhotoEdit] = []
    private let limit: Int

    public init(limit: Int = 100) {
        self.limit = max(limit, 1)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public mutating func show(_ e: PhotoEdit) { current = e }

    public mutating func commit() {
        guard current != committed else { return }
        past.append(committed)
        if past.count > limit { past.removeFirst(past.count - limit) }
        committed = current
        future.removeAll()
    }

    public mutating func set(_ e: PhotoEdit) {
        show(e)
        commit()
    }

    public mutating func reset() { set(.original) }

    public mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append(committed)
        committed = previous
        current = previous
    }

    public mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(committed)
        committed = next
        current = next
    }
}
