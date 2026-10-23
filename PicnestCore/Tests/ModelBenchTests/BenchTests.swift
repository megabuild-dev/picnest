import Foundation
import Testing
import PicnestCore
@testable import ModelBench

struct BenchTests {
    // 3 categories. Photos 0-3 are right, photo 4 is wrong (label 2, best 0), photo 5 is wrong (label 1, second is 1).
    static let photos: [ScoredPhoto] = [
        .init(label: 0, scores: [0.30, 0.10, 0.05]),
        .init(label: 1, scores: [0.05, 0.28, 0.10]),
        .init(label: 2, scores: [0.10, 0.05, 0.31]),
        .init(label: 0, scores: [0.26, 0.20, 0.10]),
        .init(label: 2, scores: [0.29, 0.10, 0.252]),
        .init(label: 1, scores: [0.28, 0.272, 0.05]),
    ]

    @Test func top2Order() {
        let t = top2([0.1, 0.3, 0.2])
        #expect(t.best == 1 && t.second == 2)
        #expect(abs(t.margin - 0.1) < 1e-6)
    }

    @Test func agreementTop1AndTop2() {
        let a = agreement(Self.photos)
        #expect(abs(a.top1 - 4.0 / 6) < 1e-9)
        #expect(a.top2 == 1.0)
        #expect(agreement([]).top1 == 0)
    }

    @Test func categoryScoreIsMaxPrompt() throws {
        let s = categoryScores(image: [1, 0], prompts: [[1, 0], [0, 1], [0.6, 0.8]], promptCategory: [0, 0, 1], categoryCount: 2)
        try #require(s.count >= 2)
        #expect(abs(s[0] - 1) < 1e-6 && abs(s[1] - 0.6) < 1e-6)
    }

    @Test func thresholdsExactChoice() throws {
        // Wrong photos have margins 0.038 and 0.008 (off the 0.005 grid). Marking both uncertain needs minMargin 0.04.
        // That makes 2 of 6 uncertain (33.3%, allowed at 0.34) and the 4 certain photos are all right.
        let c = try #require(searchThresholds(Self.photos, maxUncertain: 0.34))
        #expect(abs(c.minScore - 0.10) < 1e-6)
        #expect(abs(c.minMargin - 0.04) < 1e-6)
        #expect(abs(c.uncertainFraction - 2.0 / 6) < 1e-9)
        #expect(c.agreement == 1.0)
        // With only 1 uncertain photo allowed (16.7%), only the 0.008 margin photo can go: 4 right of 5.
        let tight = try #require(searchThresholds(Self.photos, maxUncertain: 0.17))
        #expect(abs(tight.minMargin - 0.01) < 1e-6)
        #expect(abs(tight.uncertainFraction - 1.0 / 6) < 1e-9)
        #expect(abs(tight.agreement - 4.0 / 5) < 1e-9)
    }

    @Test func uncertainRuleBoundaries() {
        let t = Top2(best: 0, second: 1, bestScore: 0.5, secondScore: 0.25)  // margin 0.25 (exact in Float)
        #expect(!isUncertain(t, minScore: 0.5, minMargin: 0.25))   // equal is not uncertain
        #expect(isUncertain(t, minScore: 0.51, minMargin: 0.25))    // best below minScore
        #expect(isUncertain(t, minScore: 0.5, minMargin: 0.26))    // margin below minMargin
        #expect(!isUncertain(t, minScore: 0.10, minMargin: 0.01))
    }

    @Test func thresholdsEmpty() {
        #expect(searchThresholds([]) == nil)
    }

    @Test func temperaturePicksInRange() throws {
        // Margin 0.02 between 2 categories: T=0.005 gives ~98%, 0.01 gives ~88%, 0.02 gives ~73%, 0.05 gives ~60%.
        let photos = [ScoredPhoto(label: 0, scores: [0.30, 0.28])]
        let sel = try #require(selectTemperature(photos))
        #expect(sel.inRange)
        #expect((60.0...95.0).contains(sel.meanPercent))
        #expect(sel.temperature != 0.005)
    }

    @Test func temperatureFallsBackWhenNoneInRange() throws {
        let photos = [ScoredPhoto(label: 0, scores: [0.30] + Array(repeating: 0.299, count: 9))]
        let sel = try #require(selectTemperature(photos))
        #expect(!sel.inRange)
        #expect(sel.temperature == 0.005)  // sharpest temperature is closest to the range
    }

    @Test func fitLinearRecoversLine() {
        let f = fitLinear([(0.0, 0.1), (0.5, 0.2), (1.0, 0.3)])
        #expect(abs(f.scale - 0.2) < 1e-5 && abs(f.offset - 0.1) < 1e-5)
        #expect(fitLinear([(0.5, 0.2)]) == (1, 0))
        #expect(fitLinear([(0.5, 0.2), (0.5, 0.3)]) == (1, 0))
    }

    @Test func exampleScoreMeanOfTop3() throws {
        let image: Vector = [1, 0]
        let ex: [Vector] = [[1, 0], [0.8, 0.6], [0.6, 0.8], [0, 1]]   // cosines 1, 0.8, 0.6, 0
        let s = try #require(VectorMath.exampleScore(image: image, examples: ex))
        #expect(abs(s - 0.8) < 1e-6)            // (1 + 0.8 + 0.6) / 3
        let two = try #require(VectorMath.exampleScore(image: image, examples: [[0.8, 0.6], [0.6, 0.8]]))
        #expect(abs(two - 0.7) < 1e-6)          // fewer than 3: mean of all
        #expect(VectorMath.exampleScore(image: image, examples: []) == nil)
    }

    @Test func exampleScaleKnownFit() {
        // Label 0: 4 photos (3 examples each). Label 1: 2 photos (1 example each).
        let images: [Vector] = [[1, 0], [0.8, 0.6], [0.6, 0.8], [0, 1], [1, 0], [0.6, 0.8]]
        // Photo 0 examples are 1,2,3: cos 0.8, 0.6, 0 -> mean(all 3) = 0.4667. Computed by hand below.
        let labels = [0, 0, 0, 0, 1, 1]
        // Prompt score of the label category is the line y = 0.5 x + 0.1 of the example score x.
        // The other category stays at 0, so every photo is classified correctly.
        var photos: [ScoredPhoto] = []
        var xs: [Float] = []
        for i in 0..<6 {
            let others = (0..<6).filter { $0 != i && labels[$0] == labels[i] }.map { images[$0] }
            let x = VectorMath.exampleScore(image: images[i], examples: others)!
            xs.append(x)
            var scores: [Float] = [0, 0]
            scores[labels[i]] = 0.5 * x + 0.1
            photos.append(ScoredPhoto(label: labels[i], scores: scores))
        }
        let fit = fitExampleScale(images: images, photos: photos)
        #expect(fit.pairCount == 6)
        #expect(abs(fit.scale - 0.5) < 1e-4)
        #expect(abs(fit.offset - 0.1) < 1e-4)
        #expect(Set(xs.map { ($0 * 1000).rounded() }).count > 1)   // inputs differ, so the fit is real
    }

    @Test func exampleScaleSkipsSingletonLabels() {
        let photos = [ScoredPhoto(label: 0, scores: [0.3, 0.1]), ScoredPhoto(label: 1, scores: [0.1, 0.3])]
        let fit = fitExampleScale(images: [[1, 0], [0, 1]], photos: photos)
        #expect(fit.pairCount == 0 && fit.scale == 1 && fit.offset == 0)
    }

    @Test func confusionCountsWrongPairsOnly() {
        let photos = Self.photos + [.init(label: 2, scores: [0.29, 0.1, 0.25])]
        let pairs = confusionPairs(photos)
        #expect(pairs.first == ConfusionPair(label: 2, predicted: 0, count: 2))
        #expect(pairs.contains(ConfusionPair(label: 1, predicted: 0, count: 1)))
        #expect(pairs.count == 2)
        #expect(confusionPairs(photos, limit: 1).count == 1)
    }

    @Test func csvRoundTripWithQuotes() {
        let rows = [["file", "label"], ["a,b.jpg", "Kids' \"art\""], ["c.jpg", ""]]
        #expect(parseCSV(writeCSV(rows)) == rows)
    }

    @Test func csvHandlesCRLFAndBlankLines() {
        #expect(parseCSV("a,b\r\n\r\nc,d\r\n") == [["a", "b"], ["c", "d"]])
        #expect(parseCSV("a,b\nc,") == [["a", "b"], ["c", ""]])
    }

    @Test func labelsTolerateBadInput() throws {
        let names = ["Kids' artwork", "Food", "Receipts"]
        let csv = "file,label\n1.jpg,food\n2.jpg,  KIDS'   Artwork \n3.jpg,\n4.jpg,Pets\n5.jpg\n6.jpg,Kids\u{2019} artwork\n"
        let r = parseLabels(csv: csv, names: names)
        #expect(r.labels == ["1.jpg": 1, "2.jpg": 0, "6.jpg": 0])
        #expect(r.emptyFiles == ["3.jpg", "5.jpg"])
        try #require(r.unknown.count >= 1)
        #expect(r.unknown.count == 1 && r.unknown[0].file == "4.jpg" && r.unknown[0].label == "Pets")
    }

    @Test func planCategoriesByFileName() {
        let csv = "source,destination,category,score\n/x/photos/a.jpg,/y/a.jpg,food,0.3\n/x/photos/b.jpg,/y/b.jpg,_uncertain,0.1\n"
        #expect(parsePlanCategories(csv: csv, photosRoot: "/x/photos") == ["a.jpg": "food", "b.jpg": "_uncertain"])
    }

    @Test func planMatchesRelativePathNotBaseName() {
        let csv = "source,category\n/x/photos/a.jpg,food\n/x/photos/sub/a.jpg,pets\n/elsewhere/a.jpg,pets\n/x/photos2/a.jpg,pets\n"
        let m = parsePlanCategories(csv: csv, photosRoot: "/x/photos")
        #expect(m == ["a.jpg": "food", "sub/a.jpg": "pets"])
        #expect(relativePath(of: "/x/photos", root: "/x/photos") == nil)
    }

    @Test func slugsAreCLIValid() throws {
        #expect(slug("Kids' artwork") == "kids-artwork")
        #expect(slug("Family outings") == "family-outings")
        #expect(uniqueSlugs(["Food", "food!", "Pets"]) == ["food", "food-2", "pets"])
        for c in try CandidateRepository().load(.everyday) {
            #expect(slug(c.displayName).wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil)
        }
    }

    @Test func yamlHasSlugsAndPrompts() {
        let y = categoriesYAML([Candidate(displayName: "Kids' artwork", emoji: "x", prompts: ["a \"b\"", "c"])])
        #expect(y.contains("- slug: kids-artwork"))
        #expect(y.contains("- \"a \\\"b\\\"\""))
        #expect(y.hasPrefix("settings:"))
    }

    @Test func sampleIsSeededAndSorted() {
        let urls = (0..<100).map { URL(fileURLWithPath: "/p/\($0).jpg") }
        let a = pickSample(urls.reversed(), count: 50, seed: 1)
        let b = pickSample(urls, count: 50, seed: 1)
        let c = pickSample(urls, count: 50, seed: 2)
        #expect(a == b && a.count == 50 && Set(a).count == 50)
        #expect(a != c)
        #expect(pickSample(Array(urls.prefix(5)), count: 50, seed: 1).count == 5)
    }

    @Test func supportedPhotoTypes() {
        for ok in ["a.jpg", "a.JPEG", "a.Png", "a.heic", "a.HEIF", "a.webp", "a.gif", "a.tiff"] {
            #expect(isSupportedPhoto(URL(fileURLWithPath: "/x/\(ok)")), "\(ok)")
        }
        for bad in ["a.html", "a.mp4", ".hidden.jpg", "a", "a.zip"] {
            #expect(!isSupportedPhoto(URL(fileURLWithPath: "/x/\(bad)")), "\(bad)")
        }
    }

    @Test func uniqueNames() {
        #expect(uniqueName("a.jpg", taken: []) == "a.jpg")
        #expect(uniqueName("a.jpg", taken: ["a.jpg", "a-2.jpg"]) == "a-3.jpg")
    }

    @Test func htmlEscapesNames() {
        let h = labelsHTML(files: ["a<b>.jpg"], names: ["Kids' & art"])
        #expect(h.contains("a&lt;b&gt;.jpg") && h.contains("Kids' &amp; art"))
    }
}
