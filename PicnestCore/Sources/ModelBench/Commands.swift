import Foundation
import PicnestCore

// File IO and orchestration for the ModelBench subcommands. The logic is in Bench.swift.

struct UsageError: Error, CustomStringConvertible { var description: String }

func expandPath(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }

/// Value of `--name`, or `default`. Removes the option from `args`.
func takeOption(_ name: String, from args: inout [String]) throws -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { throw UsageError(description: "\(name) needs a value") }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func parseNumber<T: LosslessStringConvertible>(_ text: String?, name: String, default value: T) throws -> T {
    guard let text else { return value }
    guard let n = T(text) else { throw UsageError(description: "\(name) needs a whole number, got \"\(text)\"") }
    return n
}

// MARK: sample

func runSample(_ input: [String]) throws {
    var args = input
    let count = try parseNumber(try takeOption("--count", from: &args), name: "--count", default: 50 as Int)
    let seed = try parseNumber(try takeOption("--seed", from: &args), name: "--seed", default: 1 as UInt64)
    guard count > 0 else { throw UsageError(description: "--count must be greater than 0") }
    guard args.count == 2 else { throw UsageError(description: "usage: sample <folder> <out> [--count 50] [--seed 1]") }
    let source = expandPath(args[0]), out = expandPath(args[1])
    let fm = FileManager.default
    for name in ["labels.csv", "photos"] where fm.fileExists(atPath: out.appending(path: name).path) {
        throw UsageError(description: "\(out.appending(path: name).path) already exists. Nothing was changed. Use a new output folder, or remove it yourself if you want to start over.")
    }

    guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { throw UsageError(description: "cannot read \(source.path)") }
    var photos: [URL] = []
    for case let url as URL in walker where isSupportedPhoto(url) {
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { photos.append(url) }
    }
    let picked = pickSample(photos, count: count, seed: seed)

    let photosDir = out.appending(path: "photos", directoryHint: .isDirectory)
    try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
    var taken = Set<String>()
    var names: [String] = []
    for url in picked {
        let name = uniqueName(url.lastPathComponent, taken: taken)
        taken.insert(name)
        try fm.copyItem(at: url, to: photosDir.appending(path: name))   // copy only, the source never changes
        names.append(name)
    }
    names.sort()
    let everyday = try CandidateRepository().load(.everyday).map(\.displayName)
    try writeCSV([["file", "label"]] + names.map { [$0, ""] }).write(to: out.appending(path: "labels.csv"), atomically: true, encoding: .utf8)
    try labelsHTML(files: names, names: everyday).write(to: out.appending(path: "labels.html"), atomically: true, encoding: .utf8)
    print("Found \(photos.count) photos. Copied \(names.count) to \(photosDir.path)")
    print("Fill the label column in \(out.appending(path: "labels.csv").path) using the names in labels.html")
}

// MARK: categories

func runCategories(_ args: [String]) throws {
    guard args.count == 1 else { throw UsageError(description: "usage: categories <out>") }
    let out = expandPath(args[0])
    let candidates = try CandidateRepository().load(.everyday)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try categoriesYAML(candidates).write(to: out.appending(path: "categories.yaml"), atomically: true, encoding: .utf8)
    for (c, s) in zip(candidates, uniqueSlugs(candidates.map(\.displayName))) { print("\(s)\t\(c.displayName)") }
    print("Wrote \(out.appending(path: "categories.yaml").path)")
}

// MARK: evaluate

struct ModelResult {
    var size: MobileCLIPSize
    var photos: [ScoredPhoto]
    var images: [Vector]
    var top1: Double
    var top2: Double
    var msPerPhoto: Double
    var diskMB: Double
    var thresholds: ThresholdChoice?
    var temperature: (temperature: Float, meanPercent: Double, inRange: Bool)?
    var example: (scale: Float, offset: Float, pairCount: Int)
    var fileNames: [String]
}

func directorySize(_ url: URL) -> Int {
    guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total = 0
    for case let f as URL in e { total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    return total
}

func locateModels() -> URL? {
    // Models live in <repo>/Models. Look upward from the working directory, then from the executable.
    for start in [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()] {
        var dir = start.standardizedFileURL
        for _ in 0..<8 {
            for rel in ["Models"] {
                let c = dir.appending(path: rel, directoryHint: .isDirectory)
                if FileManager.default.fileExists(atPath: c.appending(path: "mobileclip_s0_image.mlpackage").path) { return c }
            }
            dir.deleteLastPathComponent()
        }
    }
    return nil
}

func runEvaluate(_ input: [String]) async throws {
    var args = input
    let cliPlan = try takeOption("--cli-plan", from: &args)
    let modelsOption = try takeOption("--models", from: &args)
    guard args.count == 1 else { throw UsageError(description: "usage: evaluate <out> [--cli-plan <plan.csv>] [--models <dir>]. The CLI must run on <out>/photos") }
    let out = expandPath(args[0])
    guard let modelDir = modelsOption.map(expandPath) ?? locateModels() else {
        throw UsageError(description: "models not found. Run scripts/fetch-models.sh or pass --models <dir>")
    }
    let candidates = try CandidateRepository().load(.everyday)
    let names = candidates.map(\.displayName)
    let slugs = uniqueSlugs(names)

    let csv = try String(contentsOf: out.appending(path: "labels.csv"), encoding: .utf8)
    let parsed = parseLabels(csv: csv, names: names)
    let files = parsed.labels.keys.sorted()
    guard !files.isEmpty else { throw UsageError(description: "labels.csv has no usable labels") }
    for u in parsed.unknown { print("unknown label: \(u.file) -> \"\(u.label)\" (photo excluded)") }
    print("\(files.count) labeled photos, \(parsed.emptyFiles.count) empty, \(parsed.unknown.count) unknown")

    let urls = files.map { out.appending(path: "photos").appending(path: $0) }
    var promptTexts: [String] = []
    var promptCategory: [Int] = []
    for (i, c) in candidates.enumerated() { for p in c.prompts { promptTexts.append(p); promptCategory.append(i) } }

    var results: [ModelResult] = []
    for size in MobileCLIPSize.allCases {
        print("Model \(size.rawValue)...")
        guard FileManager.default.fileExists(atPath: modelDir.appending(path: size.imagePackageName).path) else {
            print("  missing, skipped"); continue
        }
        let embedder = try CoreMLEmbedder(size: size, modelDirectory: modelDir)
        let prompts = try await embedder.embedTexts(promptTexts).map(VectorMath.normalize)
        _ = try? await embedder.embedImages([urls[0]])   // warm up, not timed
        let start = Date()
        let embedded = await embedder.embedImagesPartial(urls)
        let elapsed = Date().timeIntervalSince(start)
        var images: [Vector] = [], scored: [ScoredPhoto] = [], used: [String] = []
        for (f, u) in zip(files, urls) {
            guard case .success(let v)? = embedded[u] else { print("  unreadable: \(f) (excluded)"); continue }
            let n = VectorMath.normalize(v)
            images.append(n)
            used.append(f)
            scored.append(ScoredPhoto(label: parsed.labels[f]!, scores: categoryScores(image: n, prompts: prompts, promptCategory: promptCategory, categoryCount: candidates.count)))
        }
        let a = agreement(scored)
        let disk = Double(directorySize(modelDir.appending(path: size.imagePackageName)) + directorySize(modelDir.appending(path: size.textPackageName))) / 1_000_000
        results.append(ModelResult(
            size: size, photos: scored, images: images, top1: a.top1, top2: a.top2,
            msPerPhoto: elapsed * 1000 / Double(max(urls.count, 1)), diskMB: disk,
            thresholds: searchThresholds(scored), temperature: selectTemperature(scored),
            example: fitExampleScale(images: images, photos: scored), fileNames: used))
        print("  top1 \(percentString(a.top1)), top2 \(percentString(a.top2))")
    }
    guard !results.isEmpty else { throw UsageError(description: "no model was evaluated") }

    var cli: (agree: Double, uncertain: Int, total: Int, missing: Int)?
    if let cliPlan {
        let photosRoot = out.appending(path: "photos").path
        let plan = parsePlanCategories(csv: try String(contentsOf: expandPath(cliPlan), encoding: .utf8), photosRoot: photosRoot)
        var total = 0, uncertain = 0, correct = 0
        for f in files {
            guard let c = plan[f] else { continue }
            total += 1
            if c == "_uncertain" { uncertain += 1 } else if c == slugs[parsed.labels[f]!] { correct += 1 }
        }
        guard total > 0 else {
            throw UsageError(description: "no labeled photo was found in the CLI plan. Run `classify plan` on \(photosRoot)")
        }
        cli = (Double(correct) / Double(total), uncertain, total, files.count - total)
    }

    let report = makeReport(results: results, names: names, parsed: parsed, labeledCount: files.count, cli: cli)
    try report.write(to: out.appending(path: "report.md"), atomically: true, encoding: .utf8)
    print(report)
    print("Wrote \(out.appending(path: "report.md").path)")
}

/// Highest top-1. If another model is within 3 points, the smaller one wins (spec step 10).
func selectBest(_ results: [ModelResult]) -> ModelResult {
    let top = results.map(\.top1).max() ?? 0
    return results.filter { $0.top1 >= top - 0.03 }.min(by: { $0.diskMB < $1.diskMB }) ?? results[0]
}

func makeReport(results: [ModelResult], names: [String], parsed: LabelParse, labeledCount: Int,
                cli: (agree: Double, uncertain: Int, total: Int, missing: Int)?) -> String {
    var r = "# Phase 0 model test\n\n"
    r += "Labeled photos used: \(labeledCount). Empty labels: \(parsed.emptyFiles.count). Unknown labels: \(parsed.unknown.count).\n\n"
    if !parsed.unknown.isEmpty {
        r += "Unknown labels (photos excluded):\n\n" + parsed.unknown.map { "- \($0.file): \"\($0.label)\"" }.joined(separator: "\n") + "\n\n"
    }
    r += "| Model | Top-1 | Top-2 | ms per photo | Size on disk (MB) |\n|---|---|---|---|---|\n"
    for m in results {
        r += "| \(m.size.rawValue) | \(percentString(m.top1)) | \(percentString(m.top2)) | \(String(format: "%.1f", m.msPerPhoto)) | \(String(format: "%.0f", m.diskMB)) |\n"
    }
    if let cli {
        r += "\nCLI (ViT-B-32 plan.csv): top-1 agreement \(percentString(cli.agree)) over \(cli.total) photos, of which \(cli.uncertain) are `_uncertain` (counted as wrong). \(cli.missing) labeled photos not found in the CLI plan.\n"
    }
    let best = selectBest(results)
    r += "\nSelected model: **\(best.size.rawValue)** (highest top-1, smaller model if within 3 points).\n"
    r += "\n## Settings for each model\n\n| Model | minScore | minMargin | Uncertain | Agreement on certain | Temperature | Mean % correct | exampleScale | exampleOffset | Example pairs |\n|---|---|---|---|---|---|---|---|---|---|\n"
    for m in results {
        let t = m.thresholds, tm = m.temperature
        r += "| \(m.size.rawValue) | \(t.map { String(format: "%.2f", $0.minScore) } ?? "-") | \(t.map { String(format: "%.3f", $0.minMargin) } ?? "-") | \(t.map { percentString($0.uncertainFraction) } ?? "-") | \(t.map { percentString($0.agreement) } ?? "-") | \(tm.map { String($0.temperature) } ?? "-") | \(tm.map { String(format: "%.1f%%", $0.meanPercent) + ($0.inRange ? "" : " (out of 60-95)") } ?? "-") | \(String(format: "%.3f", m.example.scale)) | \(String(format: "%.3f", m.example.offset)) | \(m.example.pairCount) |\n"
    }
    r += "\n## Most frequent wrong pairs for \(best.size.rawValue)\n\n"
    let pairs = confusionPairs(best.photos)
    if pairs.isEmpty { r += "No wrong photos.\n" } else {
        r += "| Label | Predicted | Count |\n|---|---|---|\n"
        for p in pairs { r += "| \(names[p.label]) | \(names[p.predicted]) | \(p.count) |\n" }
    }
    return r
}
