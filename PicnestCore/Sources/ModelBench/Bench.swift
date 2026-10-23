import Foundation
import PicnestCore

// Pure logic for ModelBench. Plain arrays in, plain values out, so the tests need no models.

/// Scores of one labeled photo. `label` is an index into the category list. `scores` has 1 value per category.
struct ScoredPhoto: Equatable {
    var label: Int
    var scores: [Float]
}

// MARK: - Scoring

/// Category score = highest prompt score. `promptCategory[i]` is the category index of prompt `i`.
func categoryScores(image: Vector, prompts: [Vector], promptCategory: [Int], categoryCount: Int) -> [Float] {
    var scores = [Float](repeating: -.infinity, count: categoryCount)
    let sims = VectorMath.matmul([image], prompts)[0]
    for (i, s) in sims.enumerated() { scores[promptCategory[i]] = max(scores[promptCategory[i]], s) }
    return scores
}

struct Top2: Equatable {
    var best: Int
    var second: Int?
    var bestScore: Float
    var secondScore: Float?
    var margin: Float { bestScore - (secondScore ?? 0) }
}

func top2(_ scores: [Float]) -> Top2 {
    let order = scores.indices.sorted { scores[$0] > scores[$1] || (scores[$0] == scores[$1] && $0 < $1) }
    let best = order[0]
    let second = order.count > 1 ? order[1] : nil
    return Top2(best: best, second: second, bestScore: scores[best], secondScore: second.map { scores[$0] })
}

/// Fraction of photos whose label is the best category (top1) or one of the best 2 (top2).
func agreement(_ photos: [ScoredPhoto]) -> (top1: Double, top2: Double) {
    guard !photos.isEmpty else { return (0, 0) }
    var hit1 = 0, hit2 = 0
    for p in photos {
        let t = top2(p.scores)
        if t.best == p.label { hit1 += 1; hit2 += 1 } else if t.second == p.label { hit2 += 1 }
    }
    return (Double(hit1) / Double(photos.count), Double(hit2) / Double(photos.count))
}

// MARK: - Thresholds

struct ThresholdChoice: Equatable {
    var minScore: Float
    var minMargin: Float
    var uncertainFraction: Double
    /// Top-1 agreement over the photos that are not uncertain.
    var agreement: Double
}

let minScoreGrid: [Float] = stride(from: Float(0.10), through: 0.35, by: 0.01).map { ($0 * 100).rounded() / 100 }
let minMarginGrid: [Float] = stride(from: Float(0), through: 0.06, by: 0.005).map { ($0 * 1000).rounded() / 1000 }

/// The uncertain rule: best score below `minScore`, or best minus second below `minMargin`.
func isUncertain(_ t: Top2, minScore: Float, minMargin: Float) -> Bool {
    t.bestScore < minScore || t.margin < minMargin
}

/// Picks the grid pair with the highest agreement on certain photos, with at most `maxUncertain` uncertain.
/// Ties go to fewer uncertain photos, then to the lower thresholds.
func searchThresholds(
    _ photos: [ScoredPhoto], maxUncertain: Double = 0.2,
    minScores: [Float] = minScoreGrid, minMargins: [Float] = minMarginGrid
) -> ThresholdChoice? {
    guard !photos.isEmpty else { return nil }
    let tops = photos.map { top2($0.scores) }
    var best: ThresholdChoice?
    for ms in minScores {
        for mm in minMargins {
            var uncertain = 0, correct = 0
            for (p, t) in zip(photos, tops) {
                if isUncertain(t, minScore: ms, minMargin: mm) { uncertain += 1 } else if t.best == p.label { correct += 1 }
            }
            let fraction = Double(uncertain) / Double(photos.count)
            guard fraction <= maxUncertain else { continue }
            let certain = photos.count - uncertain
            let agree = certain == 0 ? 0 : Double(correct) / Double(certain)
            let choice = ThresholdChoice(minScore: ms, minMargin: mm, uncertainFraction: fraction, agreement: agree)
            if let b = best {
                if agree > b.agreement || (agree == b.agreement && fraction < b.uncertainFraction) { best = choice }
            } else { best = choice }
        }
    }
    return best
}

// MARK: - Temperature

let temperatureCandidates: [Float] = [0.005, 0.01, 0.02, 0.05]

/// Mean softmax percent (0-100) of the best category, over photos where the best category is the label.
func meanCorrectPercent(_ photos: [ScoredPhoto], temperature: Float) -> Double? {
    let percents = photos.compactMap { p -> Double? in
        let t = top2(p.scores)
        guard t.best == p.label else { return nil }
        return Double(VectorMath.softmax(p.scores, temperature: temperature)[t.best]) * 100
    }
    guard !percents.isEmpty else { return nil }
    return percents.reduce(0, +) / Double(percents.count)
}

/// Picks the temperature whose mean correct percent is in `range`. If several fit, the one closest to the
/// middle of the range wins. If none fit, the one closest to the range wins.
func selectTemperature(
    _ photos: [ScoredPhoto], candidates: [Float] = temperatureCandidates, range: ClosedRange<Double> = 60...95
) -> (temperature: Float, meanPercent: Double, inRange: Bool)? {
    let mid = (range.lowerBound + range.upperBound) / 2
    let rated = candidates.compactMap { t in meanCorrectPercent(photos, temperature: t).map { (t, $0) } }
    func distance(_ p: Double) -> Double { range.contains(p) ? abs(p - mid) : 1000 + min(abs(p - range.lowerBound), abs(p - range.upperBound)) }
    guard let best = rated.min(by: { distance($0.1) < distance($1.1) }) else { return nil }
    return (best.0, best.1, range.contains(best.1))
}

// MARK: - Example scale

/// Least squares fit `prompt = scale * example + offset`. Returns (1, 0) when the fit is not defined.
func fitLinear(_ pairs: [(example: Float, prompt: Float)]) -> (scale: Float, offset: Float) {
    guard pairs.count >= 2 else { return (1, 0) }
    let n = Double(pairs.count)
    let mx = pairs.reduce(0.0) { $0 + Double($1.example) } / n
    let my = pairs.reduce(0.0) { $0 + Double($1.prompt) } / n
    var sxx = 0.0, sxy = 0.0
    for p in pairs {
        let dx = Double(p.example) - mx
        sxx += dx * dx
        sxy += dx * (Double(p.prompt) - my)
    }
    guard sxx > 1e-12 else { return (1, 0) }
    let scale = sxy / sxx
    return (Float(scale), Float(my - scale * mx))
}

/// Leave-one-out example test. For each photo with a label, the examples are the other photos with the
/// same label. The example score is `VectorMath.exampleScore` (mean of the 3 highest cosines). The pair is (example score, prompt score)
/// of the label category, and only photos that the prompts classify correctly make a pair.
/// `images` must be unit vectors.
func fitExampleScale(images: [Vector], photos: [ScoredPhoto]) -> (scale: Float, offset: Float, pairCount: Int) {
    var pairs: [(example: Float, prompt: Float)] = []
    for (i, p) in photos.enumerated() where top2(p.scores).best == p.label {
        let others = photos.indices.filter { $0 != i && photos[$0].label == p.label }
        guard !others.isEmpty else { continue }
        guard let example = VectorMath.exampleScore(image: images[i], examples: others.map { images[$0] }) else { continue }
        pairs.append((example, p.scores[p.label]))
    }
    let fit = fitLinear(pairs)
    return (fit.scale, fit.offset, pairs.count)
}

// MARK: - Confusion

struct ConfusionPair: Equatable {
    var label: Int
    var predicted: Int
    var count: Int
}

/// The most frequent wrong (label, predicted) pairs, largest count first.
func confusionPairs(_ photos: [ScoredPhoto], limit: Int = 10) -> [ConfusionPair] {
    var counts: [[Int]: Int] = [:]
    for p in photos {
        let best = top2(p.scores).best
        if best != p.label { counts[[p.label, best], default: 0] += 1 }
    }
    return counts
        .map { ConfusionPair(label: $0.key[0], predicted: $0.key[1], count: $0.value) }
        .sorted { ($0.count, -$0.label, -$0.predicted) > ($1.count, -$1.label, -$1.predicted) }
        .prefix(limit).map { $0 }
}

// MARK: - CSV

/// RFC 4180 style parser: quoted fields, doubled quotes, commas and newlines inside quotes.
func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var sawContent = false
    let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
    var i = 0
    func endRow() {
        row.append(field)
        field = ""
        if !(row.count == 1 && row[0].isEmpty && !sawContent) { rows.append(row) }
        row = []
        sawContent = false
    }
    while i < chars.count {
        let c = chars[i]
        if inQuotes {
            if c == "\"" {
                if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
            } else { field.append(c) }
        } else if c == "\"" { inQuotes = true; sawContent = true }
        else if c == "," { row.append(field); field = ""; sawContent = true }
        else if c == "\n" || c == "\r\n" || c == "\r" { endRow() }
        else { field.append(c); sawContent = true }
        i += 1
    }
    if sawContent || !field.isEmpty || !row.isEmpty { endRow() }
    return rows
}

func csvEscape(_ s: String) -> String {
    s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
}

func writeCSV(_ rows: [[String]]) -> String {
    rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
}

/// Lowercase, collapse whitespace runs, and unify curly apostrophes.
func normalizeLabel(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{2019}", with: "'")
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

struct LabelParse: Equatable {
    /// File name to category index.
    var labels: [String: Int] = [:]
    var emptyFiles: [String] = []
    var unknown: [(file: String, label: String)] = []

    static func == (a: LabelParse, b: LabelParse) -> Bool {
        a.labels == b.labels && a.emptyFiles == b.emptyFiles
            && a.unknown.map { "\($0.file)|\($0.label)" } == b.unknown.map { "\($0.file)|\($0.label)" }
    }
}

/// Reads `file,label` rows. Empty labels and labels that match no name are not in `labels`.
func parseLabels(csv: String, names: [String]) -> LabelParse {
    var result = LabelParse()
    let index = Dictionary(names.enumerated().map { (normalizeLabel($1), $0) }, uniquingKeysWith: { a, _ in a })
    for (n, row) in parseCSV(csv).enumerated() {
        guard row.count >= 1 else { continue }
        let file = row[0].trimmingCharacters(in: .whitespaces)
        if n == 0, normalizeLabel(file) == "file" { continue }
        guard !file.isEmpty else { continue }
        let raw = row.count > 1 ? row[1] : ""
        if normalizeLabel(raw).isEmpty { result.emptyFiles.append(file); continue }
        if let k = index[normalizeLabel(raw)] { result.labels[file] = k } else { result.unknown.append((file, raw.trimmingCharacters(in: .whitespaces))) }
    }
    return result
}

/// Path of `source` relative to `root`, or nil if `source` is not inside `root`.
func relativePath(of source: String, root: String) -> String? {
    let src = URL(fileURLWithPath: source).resolvingSymlinksInPath().pathComponents
    let base = URL(fileURLWithPath: root).resolvingSymlinksInPath().pathComponents
    guard src.count > base.count, Array(src.prefix(base.count)) == base else { return nil }
    return src.dropFirst(base.count).joined(separator: "/")
}

/// Reads the CLI `plan.csv`. Gives the category slug for each source path relative to `photosRoot`.
/// Rows whose source is outside `photosRoot` are dropped.
func parsePlanCategories(csv: String, photosRoot: String) -> [String: String] {
    let rows = parseCSV(csv)
    guard let header = rows.first, let src = header.firstIndex(of: "source"), let cat = header.firstIndex(of: "category")
    else { return [:] }
    var out: [String: String] = [:]
    for row in rows.dropFirst() where row.count > max(src, cat) {
        if let rel = relativePath(of: row[src], root: photosRoot) { out[rel] = row[cat] }
    }
    return out
}

// MARK: - Slugs

func slug(_ name: String) -> String {
    let lowered = name.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
    var out = ""
    for ch in lowered {
        if ch.isASCII, ch.isLetter || ch.isNumber { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
    }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

/// One slug for each name. A repeated slug gets `-2`, `-3`, and so on.
func uniqueSlugs(_ names: [String]) -> [String] {
    var seen: [String: Int] = [:]
    return names.map { name in
        let base = slug(name)
        seen[base, default: 0] += 1
        return seen[base]! == 1 ? base : "\(base)-\(seen[base]!)"
    }
}

func categoriesYAML(_ candidates: [Candidate], settings: ClassifySettings = .default) -> String {
    var y = "settings:\n  min_score: \(settings.minScore)\n  min_margin: \(settings.minMargin)\ncategories:\n"
    for (c, s) in zip(candidates, uniqueSlugs(candidates.map(\.displayName))) {
        y += "  - slug: \(s)\n    prompts:\n"
        for p in c.prompts { y += "      - \(yamlQuote(p))\n" }
    }
    return y
}

private func yamlQuote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

// MARK: - Sampling

let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tiff"]

func isSupportedPhoto(_ url: URL) -> Bool {
    !url.lastPathComponent.hasPrefix(".") && photoExtensions.contains(url.pathExtension.lowercased())
}

/// Deterministic RNG (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `count` items chosen with a seeded shuffle of the sorted list. The same input and seed give the same result.
func pickSample(_ urls: [URL], count: Int, seed: UInt64) -> [URL] {
    var rng = SeededRNG(seed: seed)
    let sorted = urls.sorted { $0.path < $1.path }
    return Array(sorted.shuffled(using: &rng).prefix(count))
}

/// A destination name that is not in `taken`. Adds `-2`, `-3` before the extension.
func uniqueName(_ name: String, taken: Set<String>) -> String {
    guard taken.contains(name) else { return name }
    let ns = name as NSString
    var n = 2
    while true {
        let candidate = "\(ns.deletingPathExtension)-\(n).\(ns.pathExtension)"
        if !taken.contains(candidate) { return candidate }
        n += 1
    }
}

// MARK: - HTML and report

func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

func labelsHTML(files: [String], names: [String]) -> String {
    var h = "<!doctype html><meta charset=\"utf-8\"><title>Labels</title>\n"
    h += "<style>body{font-family:sans-serif}figure{display:inline-block;margin:6px;width:220px}img{width:220px;height:220px;object-fit:cover}figcaption{font-size:12px;word-break:break-all}</style>\n"
    h += "<h1>Write one name from this list in labels.csv for each photo</h1><ul>\n"
    for n in names { h += "<li>\(htmlEscape(n))</li>\n" }
    h += "</ul>\n"
    for f in files {
        h += "<figure><img src=\"photos/\(htmlEscape(f.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f))\" loading=\"lazy\"><figcaption>\(htmlEscape(f))</figcaption></figure>\n"
    }
    return h
}

func percentString(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
