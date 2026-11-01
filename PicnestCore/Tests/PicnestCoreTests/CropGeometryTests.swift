import Foundation
import Testing
@testable import PicnestCore

@Suite struct CropGeometryTests {
    private let fa = 4.0 / 3.0

    @Test func zeroAngleNeedsNoScale() {
        #expect(CropGeometry.straightenScale(degrees: 0, width: 400, height: 300) == 1.0)
    }

    @Test func scaleCoversTheCorners() {
        let w = 400.0, h = 300.0, deg = 10.0
        let s = CropGeometry.straightenScale(degrees: deg, width: w, height: h)
        #expect(s > 1)
        let t = -deg * .pi / 180
        for (cx, cy) in [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)] {
            let rx = (cx * cos(t) - cy * sin(t)) / s
            let ry = (cx * sin(t) + cy * cos(t)) / s
            #expect(abs(rx) <= w / 2 + 1e-9)
            #expect(abs(ry) <= h / 2 + 1e-9)
        }
        #expect(CropGeometry.straightenScale(degrees: -deg, width: w, height: h) == s)
    }

    @Test func dragStopsAtTheEdge() {
        let r = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let a = CropGeometry.drag(r, handle: .topLeft, dx: -5, dy: -5, ratio: nil, frameAspect: fa)
        #expect(a == NormalizedRect(x: 0, y: 0, width: 0.75, height: 0.75))
        let b = CropGeometry.drag(r, handle: .right, dx: 5, dy: 0, ratio: nil, frameAspect: fa)
        #expect(b.x == 0.25 && b.width == 0.75 && b.height == 0.5)
        let c = CropGeometry.drag(r, handle: .bottomRight, dx: 5, dy: 5, ratio: 1, frameAspect: fa)
        #expect(c.x >= 0 && c.y >= 0 && c.x + c.width <= 1 + 1e-12 && c.y + c.height <= 1 + 1e-12)
    }

    @Test func dragKeepsTheMinimumSide() {
        let r = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let a = CropGeometry.drag(r, handle: .bottomRight, dx: -5, dy: -5, ratio: nil, frameAspect: fa)
        #expect(a.width == 0.05 && a.height == 0.05 && a.x == 0.2 && a.y == 0.2)
        let b = CropGeometry.drag(r, handle: .left, dx: 5, dy: 0, ratio: nil, frameAspect: fa)
        #expect(abs(b.width - 0.05) < 1e-12 && abs(b.x + b.width - 0.6) < 1e-12)
        let c = CropGeometry.drag(r, handle: .topLeft, dx: 5, dy: 5, ratio: 1, frameAspect: fa)
        #expect(c.width >= 0.05 - 1e-12 && c.height >= 0.05 - 1e-12)
    }

    @Test func dragKeepsTheRatio() {
        let r = NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        for handle in CropHandle.allCases where handle != .move {
            for (dx, dy) in [(0.1, 0.05), (-0.2, 0.3), (0.5, -0.5), (-3.0, -3.0), (3.0, 3.0)] {
                let o = CropGeometry.drag(r, handle: handle, dx: dx, dy: dy, ratio: 1, frameAspect: fa)
                #expect(abs(o.width * 4 - o.height * 3) < 1e-9, "\(handle) \(dx) \(dy)")
                #expect(o.x >= -1e-12 && o.y >= -1e-12 && o.x + o.width <= 1 + 1e-9 && o.y + o.height <= 1 + 1e-9)
            }
        }
    }

    @Test func moveKeepsTheSize() {
        let r = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)
        let a = CropGeometry.drag(r, handle: .move, dx: 0.1, dy: -0.05, ratio: nil, frameAspect: fa)
        #expect(abs(a.x - 0.3) < 1e-12 && abs(a.y - 0.15) < 1e-12)
        #expect(a.width == 0.4 && a.height == 0.3)
        let b = CropGeometry.drag(r, handle: .move, dx: 9, dy: 9, ratio: nil, frameAspect: fa)
        #expect(abs(b.x - 0.6) < 1e-12 && abs(b.y - 0.7) < 1e-12 && b.width == 0.4 && b.height == 0.3)
    }

    @Test func fitSquareOnLandscapeFrame() {
        let o = CropGeometry.fit(.full, ratio: 1, frameAspect: fa)
        #expect(abs(o.width - 0.75) < 1e-12 && o.height == 1)
        #expect(abs(o.x - 0.125) < 1e-12 && o.y == 0)
    }

    @Test func fitFreeformChangesNothing() {
        let r = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(CropGeometry.fit(r, ratio: nil, frameAspect: fa) == r)
    }

    @Test func scaleIsTight() {
        // 400 x 300 at 10 deg: the tight value touches an edge.
        let t = 10.0 * .pi / 180
        let s = CropGeometry.straightenScale(degrees: 10, width: 400, height: 300)
        let needX = (200 * cos(t) + 150 * sin(t)) / 200
        let needY = (200 * sin(t) + 150 * cos(t)) / 150
        #expect(abs(s - max(needX, needY)) < 1e-12)
        #expect(abs(s - 1.21634) < 1e-4)
    }

    @Test func scaleOnAPortraitFrame() {
        let landscape = CropGeometry.straightenScale(degrees: 10, width: 400, height: 300)
        let portrait = CropGeometry.straightenScale(degrees: 10, width: 300, height: 400)
        #expect(abs(landscape - portrait) < 1e-12)
        let t = 10.0 * .pi / 180
        let s = portrait
        for (cx, cy) in [(-150.0, -200.0), (150, -200), (150, 200), (-150, 200)] {
            let rx = (cx * cos(-t) - cy * sin(-t)) / s
            let ry = (cx * sin(-t) + cy * cos(-t)) / s
            #expect(abs(rx) <= 150 + 1e-9 && abs(ry) <= 200 + 1e-9)
        }
    }

    @Test func scaleAt45DegreesOnASquare() {
        let s = CropGeometry.straightenScale(degrees: 45, width: 100, height: 100)
        #expect(abs(s - 2.0.squareRoot()) < 1e-12)
    }

    @Test func dragKeepsAThreeTwoRatio() {
        let r = NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        let ratio = 1.5
        for handle in CropHandle.allCases where handle != .move {
            for (dx, dy) in [(0.1, 0.05), (-0.2, 0.3), (0.5, -0.5), (-3.0, -3.0), (3.0, 3.0)] {
                let o = CropGeometry.drag(r, handle: handle, dx: dx, dy: dy, ratio: ratio, frameAspect: fa)
                #expect(abs(o.width * fa / o.height - ratio) < 1e-9, "\(handle) \(dx) \(dy)")
                #expect(o.x >= -1e-12 && o.y >= -1e-12 && o.x + o.width <= 1 + 1e-9 && o.y + o.height <= 1 + 1e-9)
            }
        }
    }

    @Test func tinyRectNearTheBorderStaysInside() {
        let r = NormalizedRect(x: 0.99, y: 0.5, width: 0.01, height: 0.01)
        let o = CropGeometry.drag(r, handle: .top, dx: 0, dy: -0.1, ratio: 1, frameAspect: fa)
        #expect(o.x >= 0 && o.x + o.width <= 1 + 1e-12 && o.y >= 0 && o.y + o.height <= 1 + 1e-12)
    }
}
