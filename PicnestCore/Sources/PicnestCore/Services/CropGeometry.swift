import Foundation

public enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move
}

/// Pure geometry for the crop box and the straighten angle.
/// `frameAspect` is width ÷ height of the frame in pixels.
/// `ratio` is width ÷ height of the crop in pixels.
public enum CropGeometry {
    /// The smallest scale at which the image turned by `degrees` covers the whole frame.
    public static func straightenScale(degrees: Double, width: Double, height: Double) -> Double {
        let t = abs(degrees) * .pi / 180
        let c = cos(t), s = sin(t)
        return max(1, c + (height / width) * s, c + (width / height) * s)
    }

    public static func drag(
        _ r: NormalizedRect, handle: CropHandle, dx: Double, dy: Double,
        ratio: Double?, frameAspect: Double, minSide: Double = 0.05
    ) -> NormalizedRect {
        if handle == .move {
            return NormalizedRect(
                x: clamp(r.x + dx, 0, 1 - r.width), y: clamp(r.y + dy, 0, 1 - r.height),
                width: r.width, height: r.height)
        }
        // sx, sy: which edge moves. +1 right/bottom, -1 left/top, 0 none.
        let sx: Double, sy: Double
        switch handle {
        case .topLeft: (sx, sy) = (-1, -1)
        case .top: (sx, sy) = (0, -1)
        case .topRight: (sx, sy) = (1, -1)
        case .right: (sx, sy) = (1, 0)
        case .bottomRight: (sx, sy) = (1, 1)
        case .bottom: (sx, sy) = (0, 1)
        case .bottomLeft: (sx, sy) = (-1, 1)
        case .left: (sx, sy) = (-1, 0)
        case .move: return r
        }
        // Room between the fixed edge and the border of the frame.
        let availW = sx > 0 ? 1 - r.x : r.x + r.width
        let availH = sy > 0 ? 1 - r.y : r.y + r.height

        guard let ratio, ratio > 0 else {
            var out = r
            if sx != 0 {
                let w = clamp(r.width + sx * dx, min(minSide, availW), availW)
                out.x = sx > 0 ? r.x : r.x + r.width - w
                out.width = w
            }
            if sy != 0 {
                let h = clamp(r.height + sy * dy, min(minSide, availH), availH)
                out.y = sy > 0 ? r.y : r.y + r.height - h
                out.height = h
            }
            return out
        }

        let k = frameAspect / ratio  // height = width × k, in normalized units
        let cx = r.x + r.width / 2, cy = r.y + r.height / 2
        let w: Double, h: Double
        if sx != 0 && sy != 0 {
            let want = max(r.width + sx * dx, (r.height + sy * dy) / k)
            let hi = min(availW, availH / k)
            w = clamp(want, min(max(minSide, minSide / k), hi), hi)
            h = w * k
        } else if sx != 0 {
            let hi = min(availW, 2 * min(cy, 1 - cy) / k)
            w = clamp(r.width + sx * dx, min(max(minSide, minSide / k), hi), hi)
            h = w * k
        } else {
            let hiH = min(availH, 2 * min(cx, 1 - cx) * k)
            h = clamp(r.height + sy * dy, min(max(minSide * k, minSide), hiH), hiH)
            w = h / k
        }
        let x: Double = sx > 0 ? r.x : sx < 0 ? r.x + r.width - w : cx - w / 2
        let y: Double = sy > 0 ? r.y : sy < 0 ? r.y + r.height - h : cy - h / 2
        return NormalizedRect(x: x, y: y, width: w, height: h)
    }

    /// The largest rect with `ratio` inside 0…1, centered on the center of `r`.
    public static func fit(_ r: NormalizedRect, ratio: Double?, frameAspect: Double) -> NormalizedRect {
        guard let ratio, ratio > 0 else { return r }
        let k = frameAspect / ratio
        let w = min(1, 1 / k)
        let h = w * k
        let cx = r.x + r.width / 2, cy = r.y + r.height / 2
        return NormalizedRect(
            x: clamp(cx - w / 2, 0, 1 - w), y: clamp(cy - h / 2, 0, 1 - h), width: w, height: min(h, 1))
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
