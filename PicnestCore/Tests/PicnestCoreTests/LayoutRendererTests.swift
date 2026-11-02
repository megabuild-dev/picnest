import AppKit
import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PicnestCore

/// Records what the renderer asks for. A class with a lock, because the provider is `@Sendable`.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(id: MediaID, maxPixel: Int)] = []
    func add(_ id: MediaID, _ maxPixel: Int) { lock.withLock { values.append((id, maxPixel)) } }
    var calls: [(id: MediaID, maxPixel: Int)] { lock.withLock { values } }
}

struct LayoutRendererTests {
    private typealias RGB = TestImages.RGB

    private let red: RGB = (255, 0, 0)
    private let charcoal: RGB = (58, 58, 58)
    private let source = PixelSize(width: 400, height: 300)

    private func document(photos: Int = 6, background: LayoutBackground = .charcoal) -> LayoutDocument {
        LayoutDocument(background: background, photoIDs: (0..<photos).map { "p\($0).jpg" })
    }

    private func renderer(size: PixelSize? = nil) -> LayoutRenderer {
        let size = size ?? source
        return LayoutRenderer(sizes: { _ in size })
    }

    private func render(
        _ page: LayoutPage, _ d: LayoutDocument, renderer: LayoutRenderer? = nil,
        images: @escaping LayoutImageProvider
    ) async throws -> CGImage {
        try #require(await (renderer ?? self.renderer()).image(
            of: page, document: d, fileNames: [:], dpi: 72, images: images))
    }

    private func solidRed() throws -> LayoutImageProvider {
        let image = try TestImages.solid(red, width: 400, height: 300)
        return { _, _ in image }
    }

    private func near(_ c: RGB, _ e: RGB, tol: Int = 8) -> Bool {
        abs(Int(c.r) - Int(e.r)) <= tol && abs(Int(c.g) - Int(e.g)) <= tol && abs(Int(c.b) - Int(e.b)) <= tol
    }

    private func pixel(_ image: CGImage, _ x: Double, _ y: Double) -> RGB {
        TestImages.color(at: (Int(x.rounded()), Int(y.rounded())), in: image)
    }

    @Test func pageImageHasThePixelSizeOfThePaper() async throws {
        let d = document()
        let page = LayoutEngine.pages(for: d)[0]
        let image = try await render(page, d) { _, _ in nil }
        #expect(image.width == 842 && image.height == 595)
        #expect(image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(image.bitsPerComponent == 8)
    }

    @Test func backgroundFillsTheGapsAndMargins() async throws {
        let d = document()
        let page = LayoutEngine.pages(for: d)[0]
        let image = try await render(page, d, images: try solidRed())
        #expect(near(pixel(image, 10, 10), charcoal))
        let a = page.cells[0].frame, b = page.cells[1].frame
        #expect(near(pixel(image, (a.maxX + b.x) / 2, a.y + a.height / 2), charcoal))
    }

    @Test func photoFillsItsFitRect() async throws {
        let d = document()
        let page = LayoutEngine.pages(for: d)[0]
        let image = try await render(page, d, images: try solidRed())
        let cell = page.cells[0]
        let fit = LayoutEngine.imageRect(source: source, in: cell.imageArea, fit: .fit)
        #expect(near(pixel(image, fit.x + fit.width / 2, fit.y + fit.height / 2), red))
        #expect(near(pixel(image, fit.x + fit.width / 2, fit.y - 5), charcoal))
        #expect(near(pixel(image, fit.x + fit.width / 2, fit.maxY + 5), charcoal))
    }

    @Test func fillModeClipsToTheArea() async throws {
        let d = document()
        var page = LayoutEngine.pages(for: d)[0]
        page.cells[0].fit = .fill
        let image = try await render(page, d, images: try solidRed())
        let a = page.cells[0].imageArea
        for (x, y) in [(a.x + 2, a.y + 2), (a.maxX - 3, a.y + 2), (a.x + 2, a.maxY - 3), (a.maxX - 3, a.maxY - 3)] {
            #expect(near(pixel(image, x, y), red), "inside \(x),\(y)")
        }
        let midX = a.x + a.width / 2, midY = a.y + a.height / 2
        for (x, y) in [(a.x - 2, midY), (a.maxX + 2, midY), (midX, a.y - 2), (midX, a.maxY + 2)] {
            #expect(near(pixel(image, x, y), charcoal), "outside \(x),\(y)")
        }
    }

    @Test func collageFillHasNoBackgroundInsideACell() async throws {
        var d = document()
        d.kind = .collage
        d.template = .heroLeft
        let page = LayoutEngine.pages(for: d)[0]
        let image = try await render(page, d, images: try solidRed())
        for cell in page.cells {
            let f = cell.frame
            for (x, y) in [(f.x + 2, f.y + 2), (f.maxX - 3, f.y + 2), (f.x + 2, f.maxY - 3), (f.maxX - 3, f.maxY - 3),
                           (f.x + f.width / 2, f.y + f.height / 2)] {
                #expect(near(pixel(image, x, y), red), "inside \(x),\(y)")
            }
        }
        let a = page.cells[0].frame, b = page.cells[1].frame
        #expect(near(pixel(image, (a.maxX + b.x) / 2, a.y + a.height / 2), charcoal))
    }

    @Test func quadrantImageIsUpright() async throws {
        let d = document()
        let page = LayoutEngine.pages(for: d)[0]
        let quadrants = try TestImages.quadrantImage(width: 400, height: 300)
        let image = try await render(page, d) { _, _ in quadrants }
        let r = LayoutEngine.imageRect(source: source, in: page.cells[0].imageArea, fit: .fit)
        #expect(near(pixel(image, r.x + 4, r.y + 4), (255, 0, 0)))
        #expect(near(pixel(image, r.maxX - 5, r.y + 4), (0, 255, 0)))
        #expect(near(pixel(image, r.x + 4, r.maxY - 5), (0, 0, 255)))
        #expect(near(pixel(image, r.maxX - 5, r.maxY - 5), (255, 255, 255)))
    }

    @Test func emptyCellsDrawNothing() async throws {
        let d = document(photos: 1)
        let page = LayoutEngine.pages(for: d)[0]
        let recorder = Recorder()
        let red = try solidRed()
        let image = try await render(page, d) { id, maxPixel in
            recorder.add(id, maxPixel)
            return await red(id, maxPixel)
        }
        #expect(recorder.calls.count == 1)
        let empty = page.cells[1].frame
        #expect(near(pixel(image, empty.x + empty.width / 2, empty.y + empty.height / 2), charcoal))
    }

    @Test func missingImageLeavesTheBackground() async throws {
        let d = document()
        let page = LayoutEngine.pages(for: d)[0]
        let image = try await render(page, d) { _, _ in nil }
        let c = page.cells[0].frame
        #expect(near(pixel(image, c.x + c.width / 2, c.y + c.height / 2), charcoal))
        // No size: the cell is skipped before the provider is asked.
        let noSize = LayoutRenderer(sizes: { _ in nil })
        let recorder = Recorder()
        let other = try await render(page, d, renderer: noSize) { id, maxPixel in
            recorder.add(id, maxPixel)
            return nil
        }
        #expect(recorder.calls.isEmpty)
        #expect(near(pixel(other, c.x + c.width / 2, c.y + c.height / 2), charcoal))
    }

    @Test func providerGetsOnlyTheNeededPixels() async throws {
        let d = document()
        let page = LayoutEngine.pages(for: d)[0]
        let big = PixelSize(width: 4000, height: 3000)
        let recorder = Recorder()
        let red = try solidRed()
        _ = try await render(page, d, renderer: renderer(size: big)) { id, maxPixel in
            recorder.add(id, maxPixel)
            return await red(id, maxPixel)
        }
        let calls = recorder.calls
        #expect(calls.count == 6)
        for call in calls {
            let cell = try #require(page.cells.first { $0.mediaID == call.id })
            let needed = LayoutEngine.neededPixels(for: cell.imageArea, source: big, fit: cell.fit, dpi: 72)
            #expect(call.maxPixel > 0 && call.maxPixel <= needed)
            #expect(call.maxPixel < 4000)
        }
    }

    @Test func pageLooksTheSameInEachAppearance() async throws {
        let d = LayoutDocument(background: .charcoal, showsFileNames: true, title: "Trip", note: "Hanoi",
                               photoIDs: ["p0.jpg"])
        let page = LayoutEngine.pages(for: d)[0]
        let red = try solidRed()
        let saved = NSAppearance.current
        defer { NSAppearance.current = saved }
        var bytes: [Data] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance.current = NSAppearance(named: name)
            let image = try #require(await renderer().image(
                of: page, document: d, fileNames: ["p0.jpg": "p0.jpg"], dpi: 72, images: red))
            bytes.append(try #require(image.dataProvider?.data as Data?))
        }
        #expect(bytes[0] == bytes[1])
    }

    @Test func textIsDrawnInTheFooterAndCaption() async throws {
        let blank = LayoutDocument(background: .white, photoIDs: [])
        let titled = LayoutDocument(background: .white, title: "Trip to Hanoi", note: "Spring", photoIDs: [])
        let page = LayoutEngine.pages(for: blank)[0]
        let a = try await render(page, blank) { _, _ in nil }
        let b = try await render(LayoutEngine.pages(for: titled)[0], titled) { _, _ in nil }
        #expect(a.dataProvider?.data as Data? != b.dataProvider?.data as Data?)
        let footer = try #require(page.footer)
        // Dark text on white: some pixel in the footer is not white.
        var dark = false
        for x in stride(from: Int(footer.x), to: Int(footer.x + 200), by: 1) where !dark {
            for y in Int(footer.y)..<Int(footer.maxY) where TestImages.color(at: (x, y), in: b).r < 200 {
                dark = true
                break
            }
        }
        #expect(dark)
    }

    @Test func downsampledIsUprightAndNotCached() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "six.jpg")
        try TestImages.writeQuadrants(to: url, type: .jpeg, width: 80, height: 40, orientation: 6)
        let images = ImageRepository()
        let first = try #require(images.downsampled(at: url, maxPixel: 100))
        #expect(first.width == 40 && first.height == 80)
        #expect(near(TestImages.color(at: (3, 3), in: first), (255, 0, 0)))
        let second = try #require(images.downsampled(at: url, maxPixel: 100))
        #expect(first !== second)
        #expect(images.downsampled(at: dir.url.appending(path: "none.jpg"), maxPixel: 100) == nil)
    }
}
