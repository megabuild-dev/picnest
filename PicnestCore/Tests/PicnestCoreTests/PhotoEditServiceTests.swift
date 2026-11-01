import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PicnestCore

struct PhotoEditServiceTests {
    let service = PhotoEditService(thumbnails: ThumbnailService(images: ImageRepository()), images: ImageRepository())

    private func quadrants(_ w: Int = 40, _ h: Int = 20) throws -> CGImage {
        try TestImages.quadrantImage(width: w, height: h)
    }

    private func isColor(_ c: TestImages.RGB, _ r: Int, _ g: Int, _ b: Int, tol: Int = 8) -> Bool {
        abs(Int(c.r) - r) <= tol && abs(Int(c.g) - g) <= tol && abs(Int(c.b) - b) <= tol
    }

    private func corners(_ image: CGImage) -> (tl: TestImages.RGB, tr: TestImages.RGB, bl: TestImages.RGB, br: TestImages.RGB) {
        let m = 3, w = image.width, h = image.height
        return (TestImages.color(at: (m, m), in: image), TestImages.color(at: (w - 1 - m, m), in: image),
                TestImages.color(at: (m, h - 1 - m), in: image), TestImages.color(at: (w - 1 - m, h - 1 - m), in: image))
    }

    private func expect(_ image: CGImage, size: (Int, Int), tl: (Int, Int, Int), tr: (Int, Int, Int),
                        bl: (Int, Int, Int), br: (Int, Int, Int), sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(image.width == size.0 && image.height == size.1, sourceLocation: sourceLocation)
        let c = corners(image)
        #expect(isColor(c.tl, tl.0, tl.1, tl.2), "tl \(c.tl)", sourceLocation: sourceLocation)
        #expect(isColor(c.tr, tr.0, tr.1, tr.2), "tr \(c.tr)", sourceLocation: sourceLocation)
        #expect(isColor(c.bl, bl.0, bl.1, bl.2), "bl \(c.bl)", sourceLocation: sourceLocation)
        #expect(isColor(c.br, br.0, br.1, br.2), "br \(c.br)", sourceLocation: sourceLocation)
    }

    private let red = (255, 0, 0), green = (0, 255, 0), blue = (0, 0, 255), white = (255, 255, 255)

    @Test func originalEditKeepsSizeAndPixels() throws {
        let out = try #require(service.apply(.original, to: try quadrants()))
        expect(out, size: (40, 20), tl: red, tr: green, bl: blue, br: white)
    }

    @Test func rotateRightTurnsClockwise() throws {
        var e = PhotoEdit.original
        e.rotate(clockwise: true)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (20, 40), tl: blue, tr: red, bl: white, br: green)
    }

    @Test func rotateLeftTurnsCounterclockwise() throws {
        var e = PhotoEdit.original
        e.rotate(clockwise: false)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (20, 40), tl: green, tr: white, bl: red, br: blue)
    }

    @Test func flipHorizontalSwapsLeftAndRight() throws {
        var e = PhotoEdit.original
        e.flip(horizontal: true)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (40, 20), tl: green, tr: red, bl: white, br: blue)
    }

    @Test func flipVerticalSwapsTopAndBottom() throws {
        var e = PhotoEdit.original
        e.flip(horizontal: false)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (40, 20), tl: blue, tr: white, bl: red, br: green)
    }

    @Test func flipAfterTurnUsesTheDisplayedFrame() throws {
        var e = PhotoEdit.original
        e.rotate(clockwise: true)
        e.flip(horizontal: true)  // Shown frame: blue red / white green, mirrored left to right.
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (20, 40), tl: red, tr: blue, bl: green, br: white)
    }

    @Test func cropLeftHalfKeepsRedAndBlue() throws {
        var e = PhotoEdit.original
        e.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (20, 20), tl: red, tr: red, bl: blue, br: blue)
    }

    @Test func cropTopLeftQuarterAfterATurnIsBlue() throws {
        var e = PhotoEdit.original
        e.rotate(clockwise: true)  // Shown: blue red / white green.
        e.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (10, 20), tl: blue, tr: blue, bl: blue, br: blue)
    }

    @Test func cropTopLeftQuarterAfterAFlipIsGreen() throws {
        var e = PhotoEdit.original
        e.flip(horizontal: true)  // Shown: green red / white blue.
        e.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let out = try #require(service.apply(e, to: try quadrants()))
        expect(out, size: (20, 10), tl: green, tr: green, bl: green, br: green)
    }

    /// The share of sampled pixels where `a` and `b` differ by more than 40 in a channel.
    private func mismatch(_ a: CGImage, _ b: CGImage, mirrorX: Bool, mirrorY: Bool) -> Double {
        var bad = 0, total = 0
        for y in stride(from: 2, to: a.height - 2, by: 5) {
            for x in stride(from: 2, to: a.width - 2, by: 5) {
                let ca = TestImages.color(at: (x, y), in: a)
                let cb = TestImages.color(at: (mirrorX ? a.width - 1 - x : x, mirrorY ? a.height - 1 - y : y), in: b)
                total += 1
                if abs(Int(ca.r) - Int(cb.r)) > 40 || abs(Int(ca.g) - Int(cb.g)) > 40 || abs(Int(ca.b) - Int(cb.b)) > 40 { bad += 1 }
            }
        }
        return Double(bad) / Double(total)
    }

    @Test func flipAfterStraightenIsTheMirrorOfTheStraightenedImage() throws {
        var straight = PhotoEdit.original
        straight.straighten = 5
        let base = try #require(service.apply(straight, to: try quadrants(400, 200)))
        var h = straight; h.flip(horizontal: true)
        var v = straight; v.flip(horizontal: false)
        let flippedH = try #require(service.apply(h, to: try quadrants(400, 200)))
        let flippedV = try #require(service.apply(v, to: try quadrants(400, 200)))
        #expect(mismatch(flippedH, base, mirrorX: true, mirrorY: false) < 0.02)
        #expect(mismatch(flippedV, base, mirrorX: false, mirrorY: true) < 0.02)
        // The mirror is not the same as the picture itself, so the test can fail.
        #expect(mismatch(flippedH, base, mirrorX: false, mirrorY: false) > 0.1)
    }

    @Test func croppingFalseKeepsTheWholeFrame() throws {
        var e = PhotoEdit.original
        e.rotate(clockwise: true)
        e.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let out = try #require(service.apply(e, to: try quadrants(), cropping: false))
        #expect(out.width == 20 && out.height == 40)
    }

    @Test func straightenFillsTheCorners() throws {
        var e = PhotoEdit.original
        e.straighten = 5
        let out = try #require(service.apply(e, to: try quadrants(400, 200)))
        #expect(out.width == 400 && out.height == 200)
        for p in [(0, 0), (out.width - 1, 0), (0, out.height - 1), (out.width - 1, out.height - 1)] {
            #expect(TestImages.rgba(at: p, in: out).a == 255, "corner \(p)")
        }
    }

    @Test func straightenPositiveTurnsClockwise() throws {
        var e = PhotoEdit.original
        e.straighten = 10
        let out = try #require(service.apply(e, to: try quadrants(400, 200)))
        // The red-green border starts at x = 200. Above the centre, a clockwise turn moves it to the right.
        let near = TestImages.color(at: (205, 30), in: out)
        let far = TestImages.color(at: (225, 30), in: out)
        #expect(isColor(near, 255, 0, 0, tol: 30), "\(near)")
        #expect(isColor(far, 0, 255, 0, tol: 30), "\(far)")
    }

    @Test func exifOrientationSixPreviewIsUpright() async throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "o6.jpg")
        try TestImages.writeQuadrants(to: url, type: .jpeg, width: 40, height: 20, orientation: 6)
        let out = try #require(await service.preview(at: url))
        #expect(out.width == 20 && out.height == 40)
        let c = corners(out)
        #expect(isColor(c.tl, 255, 0, 0, tol: 40), "tl \(c.tl)")  // JPEG is lossy.
        #expect(isColor(c.tr, 0, 255, 0, tol: 40))
        #expect(isColor(c.bl, 0, 0, 255, tol: 40))
    }

    @Test func outputSizeMatchesApply() throws {
        var edits: [PhotoEdit] = [.original]
        var a = PhotoEdit.original; a.rotate(clockwise: true); edits.append(a)
        var b = PhotoEdit.original; b.crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.55, height: 0.33); edits.append(b)
        var c = a; c.crop = NormalizedRect(x: 0.33, y: 0.07, width: 0.41, height: 0.77); c.flip(horizontal: true); edits.append(c)
        var d = PhotoEdit.original; d.straighten = -7; d.crop = NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5); edits.append(d)
        for (i, e) in edits.enumerated() {
            let out = try #require(service.apply(e, to: try quadrants(101, 53)))
            let size = PhotoEditService.outputSize(of: e, source: PixelSize(width: 101, height: 53))
            #expect(size == PixelSize(width: out.width, height: out.height), "edit \(i)")
        }
    }

    @Test func previewAndFullSizeHaveTheSameAspect() throws {
        var e = PhotoEdit.original
        e.rotate(clockwise: true)
        e.crop = NormalizedRect(x: 0.1, y: 0.1, width: 0.6, height: 0.7)
        let small = try #require(service.apply(e, to: try quadrants(40, 20)))
        let big = try #require(service.apply(e, to: try quadrants(400, 200)))
        #expect(abs(Double(big.width) / 10 - Double(small.width)) <= 1)
        #expect(abs(Double(big.height) / 10 - Double(small.height)) <= 1)
    }

    @Test func positiveExposureMakesGrayBrighter() throws {
        var e = PhotoEdit.original
        e[.exposure] = 50
        let out = try #require(service.apply(e, to: try TestImages.solid((100, 100, 100))))
        #expect(TestImages.color(at: (4, 4), in: out).r > 115)
    }

    @Test func zeroSaturationMakesRedGray() throws {
        var e = PhotoEdit.original
        e[.saturation] = -100
        let out = try #require(service.apply(e, to: try TestImages.solid((255, 0, 0))))
        let c = TestImages.color(at: (4, 4), in: out)
        #expect(abs(Int(c.r) - Int(c.g)) <= 8 && abs(Int(c.g) - Int(c.b)) <= 8, "\(c)")
    }

    @Test func positiveWarmthMakesRedHigherThanBlue() throws {
        var e = PhotoEdit.original
        e[.warmth] = 100
        let out = try #require(service.apply(e, to: try TestImages.solid((128, 128, 128))))
        let c = TestImages.color(at: (4, 4), in: out)
        #expect(c.r > c.b, "\(c)")
        e[.warmth] = -100
        let cool = TestImages.color(at: (4, 4), in: try #require(service.apply(e, to: try TestImages.solid((128, 128, 128)))))
        #expect(cool.b > cool.r, "\(cool)")
    }

    @Test func positiveContrastSpreadsDarkAndLight() throws {
        var e = PhotoEdit.original
        e[.contrast] = 100
        let dark = TestImages.color(at: (4, 4), in: try #require(service.apply(e, to: try TestImages.solid((64, 64, 64)))))
        let light = TestImages.color(at: (4, 4), in: try #require(service.apply(e, to: try TestImages.solid((192, 192, 192)))))
        #expect(dark.r < 64 && light.r > 192, "\(dark) \(light)")
    }

    @Test func filterValuesFollowTheTable() {
        var e = PhotoEdit.original
        var v = PhotoEditService.filterValues(for: e)
        #expect(v.ev == 0 && v.contrast == 1 && v.saturation == 1 && v.targetKelvin == 6500)
        e[.exposure] = 100; e[.contrast] = -100; e[.saturation] = 100; e[.warmth] = 100
        v = PhotoEditService.filterValues(for: e)
        #expect(v.ev == 2 && v.contrast == 0.75 && v.saturation == 2)
        #expect(v.targetKelvin == 4500)  // +100 warms the picture: the target neutral is the cooler 4500 K.
    }
}
