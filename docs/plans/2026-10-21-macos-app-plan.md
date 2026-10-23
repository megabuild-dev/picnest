---
id: picnest-macos-app-plan
title: Picnest macOS App Implementation Plan
type: plan
status: active
tags: [picnest, macos, swiftui, coreml, plan]
links:
  - "[[2026-10-21-macos-app-design]]"
  - "[[dictionary]]"
  - "[[BUILD]]"
---

# Picnest macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Picnest, a native macOS SwiftUI app. It sorts a folder of photos into category folders with an on-device Core ML CLIP model. The user fixes categories before 1 batch sort.

**Architecture:** A local Swift package `PicnestCore` holds the domain types, repositories, and services. Its unit tests use a fake embedder and need no model. An XcodeGen project holds the SwiftUI app target: views and `@Observable` view models only. A command-line tool `ModelBench` in the same package does the phase 0 model test.

**Tech Stack:** Swift 6 (language mode 6), SwiftUI, Core ML, ImageIO, Accelerate, Quick Look, Swift Testing, XcodeGen, Apple MobileCLIP Core ML models.

**Spec:** [[2026-10-21-macos-app-design]] (`docs/specs/2026-10-21-macos-app-design.md`). The CLI reference is [CLI design](https://github.com/megabuild-dev/classifyimages/blob/main/docs/specs/2026-10-14-image-classifier-design.md). Terms: [[dictionary]]. Read the spec before each task. This plan gives section numbers (for example "spec 7.3") and does not repeat the spec text.

## Checkpoints

Update this table when a phase starts and when it ends. A new session starts at the first row that is not `done`.

| Phase | Tasks | Branch | Status |
|-------|-------|--------|--------|
| 0. Model test | 1, 2, 3, 4 | `feature/macos-app/phase-0-model-test` | done (code); Task 4 Steps 7-12 deferred, see below |
| 1. Core repositories | 5, 6, 7 | `feature/macos-app/phase-1-core` | done |
| 2. Classify and review logic | 8, 9, 10 | `feature/macos-app/phase-2-classify` | done |
| 3. Sort and undo | 11, 12 | `feature/macos-app/phase-3-sort` | done |
| 4. App shell | 13, 14, 15 | `feature/macos-app/phase-4-app-shell` | done |
| 5. Review actions | 16, 17 | `feature/macos-app/phase-5-review-actions` | done |
| 6. Sort sheet and finish | 18, 19 | `feature/macos-app/phase-6-sort-sheet` | done (Task 19 Step 6 deferred to the user) |
| Final review fixes | I1-I5, M1, M4, M5, M7, M9, M10, M11 | `feature/macos-app/final-review-fixes` | done |
| 7. Small feedback items | 20, 21 | `feature/app-feedback/phase-7-small-items` | done |
| 8. Move to Trash | 22, 23 | `feature/app-feedback/phase-8-trash` | done |
| 9. Suggested categories | 24, 25 | `feature/app-feedback/phase-9-suggestions` | done |
| 10. Duplicates | 26, 27 | `feature/app-feedback/phase-10-duplicates` | done |
| Feedback final review fixes | I1-I4, M1-M4, M8, M9 (M5-M7, M10 open) | `feature/app-feedback/final-review-fixes` | done |
| 11. Start over and suggestions after a scan | 28, 29 | `feature/start-over/phase-11-start-over` | done |
| Phase 11 final review fixes | I1, M2-M4 | `feature/start-over/final-review-fixes` | done |
| 12. Automatic names | 30 | `feature/auto-names/phase-12-auto-names` | done (fix round: aliases, unique emojis, guarded test indexes) |

Phases 7–10 come from the user feedback of 2026-10-22 (spec R10–R15). Their main feature branch is `feature/app-feedback/main` (from `main`). Use the same workflow as phases 0–6, with `feature/app-feedback/main` in place of `feature/macos-app/main`.

### Deferred: Task 4 Steps 7-12 (model decision)

The user does not have the Zalo folder on the build Mac (2026-10-21). Task 4 Steps 7-12 wait until the user gives the folder path. Until then:

- The app uses MobileCLIP **S2** (provisional). `fetch-models.sh` keeps all sizes.
- `ClassifySettings.default` keeps the placeholder values from Task 1.
- Do Steps 7-12 before Task 19 Step 6 (the full manual run). Then update the model size and `ClassifySettings.default`.
- Task 19 Step 6 (the full manual run with 500 real photos) waits for Steps 7-12. An automated test (`EndToEndTests`) runs the same flow with 30 generated photos. The manual checklist is in [[BUILD]], section "Final check with real photos".

## Branch Workflow

The main feature branch is `feature/macos-app/main`. It starts from `feature/accept-uncertain`, because the spec refers to the CLI `--accept-uncertain` rule.

Start of each phase:

```bash
git checkout feature/macos-app/main
git checkout -b feature/macos-app/phase-<n>-<description>
```

End of each phase:

```bash
swift test --package-path PicnestCore        # all tests must pass
# phases 4-6 also: xcodebuild -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS' build
# set the phase row in "Checkpoints" to "done", then:
git add docs/plans/2026-10-21-macos-app-plan.md
git commit -m "docs: mark phase <n> done"
git checkout feature/macos-app/main
git merge --no-ff feature/macos-app/phase-<n>-<description> -m "merge phase <n>: <description>"
```

Commit messages have no `Co-Authored-By` line.

## Global Constraints

- macOS only. Apple silicon. Deployment target: macOS 15.0 (spec 14 default).
- No network access at run time. No photo or embedding leaves the Mac (spec 1.5).
- No App Sandbox. Hardened runtime on (spec 8).
- Interface text is English only (spec 1.1).
- Layers: Views → View models → Services → Repositories → API (spec 10). Views never call a service or a repository. Services never call `FileManager`, Core ML, or ImageIO directly.
- Domain types live in `PicnestCore/Sources/PicnestCore/Domain/` (spec 10).
- Never overwrite a file. Never delete a source file before the size check of its copy (spec 7.2, 7.3).
- The app never changes a manual pick except through the actions in spec 4.7.
- Default sort options: Copy, no date folders, no rename, "Not sure" → Accept best guess (spec 3.5).
- Date folder format `YYYY-MM`. Rename format `YYYY-MM-DD_NNN.<ext>`, lowercase extension, `.jpeg` → `.jpg`. Collision suffix ` 2`, ` 3` (spec 7.2).
- Folder names: category display name with `/` and `:` replaced by `-`. Fixed folders: `Not sure`, `Videos`, `Unreadable` (spec 7.1).
- Accent color `#C8557A`, defined 1 time as the asset color `AccentColor` (spec 6.2). Minimum window 1000 × 680 points.
- Session data: JSON files in `~/Library/Application Support/<bundle id>/Sessions/<SHA-256 of source path>/` (spec 9). Plan decision: JSON, not SwiftData.
- Bundle id: `dev.megabuild.picnest`. App name: `Picnest`.
- Model files are not in git. `scripts/fetch-models.sh` downloads them to `Models/` (git-ignored). The app target copies them into the bundle.

## Review Focus

These conditions are not in the spec text, but users will meet them. Each line has a test in the named task.

1. File and folder names with Vietnamese letters (for example `hình ảnh/ảnh 1.jpg`). macOS can return NFD or NFC forms. Expect the same media ID for both forms, and a correct sort and undo. Test in Task 5 and Task 12.
2. The source file is removed or changed after the scan, or the disk is full during the sort. Expect a stop before any file operation for a changed file, and a clean journal for a failed copy that Undo can reverse. Test in Task 12.
3. The destination folder is inside the source folder, or is the source folder. The destination must be outside the source folder. Expect the Sort sheet to refuse the source folder and each folder in it. Expect the scan to skip the default output folder. Test in Task 5 and Task 11. (Changed by the final review, I2.)
4. Category names with `/`, `:`, a leading `.`, or only spaces, and 2 categories whose folder names are the same after the replacement. Expect folder names that are valid and different (` 2` suffix). Test in Task 11.
5. The app quits during a sort, so the journal has no `done` line. Expect the app to refuse a new sort and offer Undo Last Sort. Test in Task 12.

---

## File Structure

```
picnest/
  project.yml                                XcodeGen project (Task 13)
  Picnest.xcodeproj/                     generated, committed (Task 13)
  scripts/fetch-models.sh                    downloads Core ML models (Task 3)
  Models/                                    git-ignored model files
  BUILD.md                                   build guide for each Mac (Task 19)
  PicnestCore/
    Package.swift
    Sources/PicnestCore/
      Domain/            Vector.swift, Media.swift, Category.swift, Classification.swift,
                         Sort.swift, Session.swift, Journal.swift
      Repositories/      CandidateRepository.swift, CoreMLEmbedder.swift, CLIPTokenizer.swift,
                         MediaRepository.swift, DateResolver.swift, ImageRepository.swift,
                         EmbeddingRepository.swift, SessionRepository.swift,
                         BookmarkRepository.swift, JournalRepository.swift, FileOps.swift
      Services/          VectorMath.swift, Clustering.swift, ScanService.swift,
                         ClassifyService.swift, ReviewService.swift, SortPlanner.swift,
                         SortService.swift
      Resources/         candidates-everyday.json, candidates-art.json, clip-vocab.json, clip-merges.txt
    Sources/ModelBench/  main.swift, Bench.swift
    Tests/PicnestCoreTests/
      Support/           TestImages.swift, FakeEmbedder.swift, TempDir.swift
      <one test file for each source file that has logic>
  Picnest/
    App/                 PicnestApp.swift, AppEnvironment.swift, AppModel.swift
    Welcome/             WelcomeView.swift, WelcomeViewModel.swift
    Scan/                ScanView.swift, ScanViewModel.swift
    Review/              ReviewView.swift, ReviewViewModel.swift, SidebarView.swift,
                         PhotoGridView.swift, PhotoTile.swift, SelectionBar.swift,
                         NotSureView.swift, QuickLookPreview.swift
    Sort/                SortSheet.swift, SortViewModel.swift
    Assets.xcassets/     AccentColor, AppIcon
  PicnestTests/      view model tests (Tasks 14-18)
```

---

## Phase 0: Model test

### Task 1: Package scaffold, domain types, test support

**Files:**
- Create: `PicnestCore/Package.swift`, all files in `Sources/PicnestCore/Domain/`, `Tests/PicnestCoreTests/Support/*.swift`, `Tests/PicnestCoreTests/DomainTests.swift`
- Modify: `.gitignore` (add `Models/`, `.build/`, `xcuserdata/`)

**Interfaces:**
- Produces (all `public`, all `Codable`, `Sendable`, `Hashable` where possible):
  - `typealias Vector = [Float]`
  - `enum MediaKind: String { case image, video }`
  - `typealias MediaID = String` — the relative path from the source folder, in Unicode NFC form.
  - `struct MediaFile: Identifiable { id: MediaID; relativePath: String; kind: MediaKind; size: Int64; modified: Date }`
  - `enum DateSource: String { case exif, fileNameTimestamp, modificationTime }`
  - `struct PhotoDate { date: Date; source: DateSource }`
  - `enum SkipReason: String { case webFile, archive, hidden, filesFolder, outputFolder, unsupported }`
  - `struct ScanResult { media: [MediaFile]; dates: [MediaID: PhotoDate]; skipped: [SkipReason: Int] }`
  - `typealias CategoryID = UUID`
  - `struct Category: Identifiable { id: CategoryID; displayName: String; emoji: String; prompts: [String]; exampleIDs: [MediaID]; order: Int }`
  - `struct Candidate { displayName: String; emoji: String; prompts: [String] }`
  - `enum CandidateList: String { case everyday, artStudio }`
  - `struct ClassifySettings { minScore: Float; minMargin: Float; temperature: Float; exampleScale: Float; exampleOffset: Float }` with `static let default` = `(0.22, 0.02, 0.01, 1.0, 0.0)`. Task 4 replaces these values.
  - `struct Assignment { categoryID: CategoryID; score: Float; secondCategoryID: CategoryID?; secondScore: Float?; percent: Int; uncertain: Bool }`
  - `enum PhotoState { case auto(Assignment), manual(CategoryID), heldNotSure(Assignment), dontMove, unreadable }` with computed `isNotSure: Bool` (true for `.heldNotSure`, and for `.auto` with `uncertain == true`) and `isManual: Bool`.
  - `enum SortMode: String { case copy, move }`
  - `enum NotSureChoice: String { case acceptBestGuess, notSureFolder, leaveInSource }`
  - `struct SortOptions { destination: URL; mode: SortMode; dateFolders: Bool; rename: Bool; notSureChoice: NotSureChoice }` with `static func defaults(source: URL) -> SortOptions` (destination `<source> - sorted` next to the source).
  - `struct PlanEntry { mediaID: MediaID; source: URL; destination: URL; size: Int64; modified: Date }`
  - `enum JournalOp: String { case mkdir, copy, move, done }`
  - `struct JournalEntry { op: JournalOp; source: String?; destination: String?; time: Date }`
  - `struct Session { sourcePath: String; candidateList: CandidateList; categories: [Category]; states: [MediaID: PhotoState]; scan: ScanResult; sortedAt: Date? }`
  - Test support: `TempDir` (makes and removes a temp folder), `TestImages.writeJPEG(to: URL, color: (r,g,b), exifDate: Date?)`, `TestImages.writeHEIC(...)`, `FakeEmbedder` (Task 3 protocol; returns vectors from a `[String: Vector]` table keyed by file name or text, and records the calls).

- [ ] **Step 1: Write `Package.swift`**: platforms `.macOS(.v15)`; library `PicnestCore` with resources `.process("Resources")`; executable `ModelBench` that depends on it; test target `PicnestCoreTests`; Swift language mode 6.
- [ ] **Step 2: Write the failing test `DomainTests.swift`**

```swift
@Test func photoStateNotSure() {
    let a = Assignment(categoryID: UUID(), score: 0.3, secondCategoryID: nil, secondScore: nil, percent: 40, uncertain: true)
    #expect(PhotoState.auto(a).isNotSure)
    #expect(PhotoState.heldNotSure(a.with(uncertain: false)).isNotSure)
    #expect(!PhotoState.manual(UUID()).isNotSure)
    #expect(PhotoState.manual(UUID()).isManual)
}
@Test func sessionRoundTripsThroughJSON() throws { /* encode a Session with every PhotoState case, decode, #expect equal */ }
@Test func defaultSortOptions() {
    let o = SortOptions.defaults(source: URL(filePath: "/x/Zalo export"))
    #expect(o.destination.path == "/x/Zalo export - sorted")
    #expect(o.mode == .copy && !o.dateFolders && !o.rename && o.notSureChoice == .acceptBestGuess)
}
@Test func testImagesWriteExifDate() throws { /* write JPEG with exifDate, read DateTimeOriginal back with ImageIO */ }
```

- [ ] **Step 3: Run `swift test --package-path PicnestCore`.** Expected: build failure (types do not exist).
- [ ] **Step 4: Write the domain types and the test support.** `Assignment.with(uncertain:)` is a small copy helper.
- [ ] **Step 5: Run the tests.** Expected: PASS.
- [ ] **Step 6: Commit** `feat(macos): add core package and domain types`.

### Task 2: Candidate lists

**Files:**
- Create: `Resources/candidates-everyday.json`, `Resources/candidates-art.json`, `Repositories/CandidateRepository.swift`, `Tests/.../CandidateRepositoryTests.swift`

**Interfaces:**
- Produces: `struct CandidateRepository { func load(_ list: CandidateList) throws -> [Candidate] }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func everydayListSize() throws {
    let c = try CandidateRepository().load(.everyday)
    #expect((40...60).contains(c.count))
    #expect(Set(c.map(\.displayName)).count == c.count)
    #expect(c.allSatisfy { !$0.prompts.isEmpty && !$0.emoji.isEmpty })
}
@Test func artListMatchesCLI() throws {
    let c = try CandidateRepository().load(.artStudio)
    #expect(c.first?.prompts == ["a watercolor painting of a city building"])
}
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Write the JSON files and the repository.** `candidates-art.json` is a port of `CANDIDATES` in `src/classifyimages/services/discover_service.py`: display name from the slug in sentence case (`artwork-cityscape` → `Artwork cityscape`), 1 emoji, the CLI prompt. `candidates-everyday.json` has 40–60 entries for family and phone photos. It must include: Kids' artwork, Family outings, Food, Receipts, Documents, Screenshots, Pets, School events, Selfies, Group photos, Babies, Birthdays, Travel and landscapes, Home and interior, Shopping and products, Memes and stickers, Chat screenshots, Text and notes, Vehicles, Flowers and plants. Give each entry 1–3 English prompts.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add candidate category lists`.

### Task 3: Core ML embedder and tokenizer

**Files:**
- Create: `scripts/fetch-models.sh`, `Repositories/CLIPTokenizer.swift`, `Resources/clip-vocab.json`, `Resources/clip-merges.txt`, `Repositories/CoreMLEmbedder.swift`, `Tests/.../CLIPTokenizerTests.swift`, `Tests/.../CoreMLEmbedderTests.swift`

**Interfaces:**
- Produces:
  - `protocol Embedder: Sendable { var dimension: Int { get }; func embedImages(_ urls: [URL]) async throws -> [Vector]; func embedTexts(_ texts: [String]) async throws -> [Vector] }`. Every returned vector is L2-normalized. An image that cannot be read gives an error of type `EmbedderError.unreadable(URL)` for that URL only (see the next line).
  - `func embedImagesPartial(_ urls: [URL]) async -> [URL: Result<Vector, Error>]` as a protocol extension that calls `embedImages` 1 URL at a time on failure.
  - `enum MobileCLIPSize: String, CaseIterable { case s0, s1, s2, b }`
  - `final class CoreMLEmbedder: Embedder { init(size: MobileCLIPSize, modelDirectory: URL) throws }`
  - `struct CLIPTokenizer { init() throws; func encode(_ text: String) -> [Int32] }` — always 77 tokens: start token 49406, the BPE tokens, end token 49407, then zeros.

- [ ] **Step 1: Write `fetch-models.sh`.** It downloads the image and text `.mlpackage` files for S0, S1, S2, and B from the Hugging Face repo `apple/coreml-mobileclip` into `Models/`. It skips files that exist. Use `curl -L` or `git lfs`; no Python. Also add `Models/` to `.gitignore` if Task 1 did not.
- [ ] **Step 2: Copy the CLIP BPE vocabulary and merges** into `Resources/`. Take them from Apple's `ml-mobileclip` iOS sample app or from OpenAI CLIP `bpe_simple_vocab_16e6`. Record the source URL and license in a comment at the top of `CLIPTokenizer.swift`.
- [ ] **Step 3: Write the failing tokenizer test**

```swift
@Test func tokenizesLikeOpenCLIP() throws {
    let t = try CLIPTokenizer().encode("a photo of a cat")
    #expect(t.count == 77)
    #expect(Array(t.prefix(7)) == [49406, 320, 1125, 539, 320, 2368, 49407])
    #expect(t[7...].allSatisfy { $0 == 0 })
}
```

- [ ] **Step 4: Run it.** Expected: FAIL.
- [ ] **Step 5: Implement `CLIPTokenizer`.** Lowercase, clean whitespace, split with the CLIP regex, byte-to-unicode map, BPE merges. Truncate to 76 tokens before the end token.
- [ ] **Step 6: Run it.** Expected: PASS.
- [ ] **Step 7: Write the model test, gated** with `.enabled(if: ProcessInfo.processInfo.environment["PICNEST_MODELS"] != nil)`:

```swift
@Test(.enabled(if: modelsAvailable)) func catImageMatchesCatText() async throws {
    let e = try CoreMLEmbedder(size: .s0, modelDirectory: modelsDir)
    let img = try await e.embedImages([fixture("cat.jpg")])[0]
    let txt = try await e.embedTexts(["a photo of a cat", "a screenshot of a phone"])
    #expect(abs(norm(img) - 1) < 1e-3)
    #expect(dot(img, txt[0]) > dot(img, txt[1]))
}
```

Add a small public-domain cat photo at `Tests/PicnestCoreTests/Fixtures/cat.jpg` (under 200 KB) and declare it as a test resource.
- [ ] **Step 8: Implement `CoreMLEmbedder`.** Load `<size>_image.mlpackage` and `<size>_text.mlpackage` with `MLModel.compileModel` (cache the compiled `.mlmodelc` in `~/Library/Caches/<bundle id>/`). Read the image input size from the model description. Make the image input with `MLFeatureValue(cgImage:constraint:options:)` and the option `.cropAndScale: VNImageCropAndScaleOption.centerCrop`. Apply the EXIF orientation first. Text input: `MLMultiArray` Int32 shape `[1, 77]`. L2-normalize all outputs. Batch images 16 at a time. `computeUnits = .all`.
- [ ] **Step 9: Run** `scripts/fetch-models.sh && PICNEST_MODELS=1 swift test --package-path PicnestCore`. Expected: PASS, including the model test.
- [ ] **Step 10: Commit** `feat(macos): add Core ML MobileCLIP embedder and CLIP tokenizer`.

### Task 4: ModelBench and the model decision (needs the user)

**Files:**
- Create: `Sources/ModelBench/main.swift`, `Sources/ModelBench/Bench.swift`, `Services/VectorMath.swift`, `Tests/.../VectorMathTests.swift`
- Modify: `docs/specs/2026-10-21-macos-app-design.md` (record results), `Domain/Classification.swift` (`ClassifySettings.default`)

**Interfaces:**
- Produces: `enum VectorMath { static func dot(_ a: Vector, _ b: Vector) -> Float; static func normalize(_ v: Vector) -> Vector; static func matmul(_ a: [Vector], _ bT: [Vector]) -> [[Float]]; static func softmax(_ x: [Float], temperature: Float) -> [Float] }`. `matmul` returns `a.count × bT.count` cosine values and uses `cblas_sgemm` from Accelerate.
- ModelBench subcommands (plain `CommandLine.arguments`, no extra package):
  - `sample <folder> <out> [--count 50] [--seed 1]` — copies 50 random photos to `<out>/photos/`, writes `<out>/labels.csv` (`file,label`, empty labels) and `<out>/labels.html` (thumbnails with file names and the list of Everyday display names).
  - `categories <out>` — writes `<out>/categories.yaml` for the CLI, with the Everyday names as slugs and their prompts.
  - `evaluate <out> [--cli-plan <plan.csv>]` — for each MobileCLIP size: embed, score with the prompts, report top-1 agreement with the labels, top-2 agreement, mean time for each photo, and model size on disk. Then search `minScore`, `minMargin`, and `temperature` (section below). If `--cli-plan` is given, also report the CLI agreement. Write `<out>/report.md`.

- [ ] **Step 1: Write the failing `VectorMathTests`**: `matmul` of 2 known unit vectors gives their cosine; `softmax([1,2,3], temperature: 1)` sums to 1 and is increasing; `softmax` with `temperature: 0.01` gives > 0.99 for the largest value.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement `VectorMath`.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Implement ModelBench.** For the threshold search, use the labeled photos. Select the (`minScore`, `minMargin`) pair from a grid that makes at most 20% of photos uncertain and has the highest agreement on the photos that are not uncertain. Select `temperature` from {0.005, 0.01, 0.02, 0.05} so that the mean percent for correct photos is 60–95%. Set `exampleScale` and `exampleOffset` by a leave-one-out test: for each labeled photo, use the other photos with the same label as examples, then fit a linear map from example score to prompt score (least squares on correct pairs).
- [ ] **Step 6: Commit** `feat(macos): add ModelBench model test tool`.
- [ ] **Step 7: USER STEP. Stop and ask the user** for the path of the Zalo folder. Run `swift run --package-path PicnestCore ModelBench sample "<zalo folder>" ~/PicnestBench`. Ask the user (or the user's wife) to fill `labels.csv` with names from `labels.html`. Wait for the user to confirm.
- [ ] **Step 8: Run the CLI comparison.** Run `ModelBench categories ~/PicnestBench`. Copy `categories.yaml` into `~/PicnestBench/photos - sorted/.classify/`. Run `uv run classify plan ~/PicnestBench/photos`.
- [ ] **Step 9: Run** `ModelBench evaluate ~/PicnestBench --cli-plan "~/PicnestBench/photos - sorted/.classify/plan.csv"`. Expected: `report.md` with 1 row for each model.
- [ ] **Step 10: Select the model.** Use the highest top-1 agreement. If 2 models are within 3 points, use the smaller one. If no model reaches 85%, still use the best model (spec 11). If `ViT-B-32` beats the best MobileCLIP by more than 10 points, stop and ask the user about the `coremltools` fallback (spec 4.1).
- [ ] **Step 11: Record the result.** Add a section "15. Phase 0 results" to the spec: the table from `report.md`, the selected size, and the final `ClassifySettings` values and score rule. Put the values in `ClassifySettings.default`. Set `fetch-models.sh` to download only the selected size by default (`--all` downloads all sizes).
- [ ] **Step 12: Run all tests, then commit** `docs: record phase 0 model results`.

---

## Phase 1: Core repositories

### Task 5: Media scan and dates

**Files:**
- Create: `Repositories/MediaRepository.swift`, `Repositories/DateResolver.swift`, tests for both

**Interfaces:**
- Produces:
  - `struct MediaRepository { func scan(source: URL, excluding: [URL]) throws -> ScanResult }` — recursive. `excluding` holds the output folder.
  - `struct DateResolver { func date(for url: URL, modified: Date) -> PhotoDate }`

- [ ] **Step 1: Write the failing tests** (use `TempDir` and `TestImages`):
  - `skipsWebFilesArchivesHiddenAndFilesFolders`: a folder with `a.jpg`, `page.html`, `x.zip`, `.DS_Store`, `site_files/b.jpg` → media `["a.jpg"]`, skipped `{webFile:1, archive:1, hidden:1, filesFolder:1}`.
  - `classifiesKinds`: `a.HEIC` → image, `v.MOV` → video, `n.txt` → skipped `.unsupported`. Supported image extensions are the spec 5 list (case-insensitive).
  - `skipsOutputFolderInsideSource` (Review Focus 3): `excluding: [source/"Zalo - sorted"]` with a photo inside it → that photo is not in media, `skipped[.outputFolder] == 1`.
  - `mediaIDIsNFC` (Review Focus 1): write `hi\u{0300}nh/a\u{0309}nh.jpg` (NFD) → `media[0].id == "hình/ảnh.jpg".precomposedStringWithCanonicalMapping`.
  - `DateResolver` tests: EXIF date wins; `1718202933221_x.jpg` with no EXIF → 2024-06-12 UTC, source `.fileNameTimestamp`; `z7913505267117_a.jpg` → `.modificationTime`; a 13-digit name with year 2220 → `.modificationTime`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Use `FileManager.enumerator(at:includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])`. Read EXIF `DateTimeOriginal` with `CGImageSourceCopyPropertiesAtIndex`. EXIF dates have no time zone: read them as local time.
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add media scan and date rules`.

### Task 6: Embedding cache and thumbnails

**Files:**
- Create: `Repositories/EmbeddingRepository.swift`, `Repositories/ImageRepository.swift`, tests for both

**Interfaces:**
- Consumes: `Embedder` (Task 3), `MediaFile` (Task 1).
- Produces:
  - `actor EmbeddingRepository { init(embedder: any Embedder, cacheDirectory: URL); func embeddings(for media: [MediaFile], source: URL, progress: @Sendable (Int, Int) -> Void) async throws -> (vectors: [MediaID: Vector], unreadable: [MediaID]); func textEmbeddings(_ texts: [String]) async throws -> [Vector] }`. The cache key is (relative path, size, modified). Files: `embeddings.index.json` (key → row) and `embeddings.f32` (rows of `dimension` floats). Save after each batch of 64, so Cancel keeps the work (spec 3.2). The method checks `Task.isCancelled` between batches. Text embeddings are cached in memory only.
  - `final class ImageRepository: Sendable { func thumbnail(for url: URL, maxPixel: Int) async -> CGImage? }` — `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways` and `kCGImageSourceCreateThumbnailWithTransform`. An `NSCache` with `totalCostLimit` 200 MB (spec 12 risk 3).

- [ ] **Step 1: Write the failing tests** with `FakeEmbedder`:
  - `secondCallUsesCache`: embed 3 files, make a new repository on the same folder, embed again → the fake embedder got 0 image calls the second time.
  - `changedFileIsEmbeddedAgain`: change the size of 1 file → 1 image call.
  - `cancelKeepsFinishedBatches`: 130 files, cancel the task after the first progress callback past 64 → a new run embeds at most 66 files.
  - `unreadableFileIsReported`: a file `bad.jpg` with random bytes → in `unreadable`, other files have vectors.
  - `thumbnailIsSmall`: a 2000×1500 JPEG → thumbnail max side ≤ 400 for `maxPixel: 400`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add embedding cache and thumbnails`.

### Task 7: Session and recent folders

**Files:**
- Create: `Repositories/SessionRepository.swift`, `Repositories/BookmarkRepository.swift`, tests for both

**Interfaces:**
- Produces:
  - `struct SessionRepository { init(root: URL); func directory(for source: URL) -> URL; func load(source: URL) throws -> Session?; func save(_ s: Session) throws; func delete(source: URL) throws }`. `root` defaults to `Application Support/dev.megabuild.picnest/Sessions`. The folder name is the SHA-256 hex (CryptoKit) of the NFC source path. `save` writes `session.json` atomically.
  - `struct RecentFolder: Codable, Identifiable { id: String; path: String; bookmark: Data; photoCount: Int; sortedAt: Date? }`
  - `struct BookmarkRepository { init(defaults: UserDefaults); func recent() -> [RecentFolder]; func remember(_ url: URL, photoCount: Int, sortedAt: Date?) throws; func resolve(_ f: RecentFolder) -> URL? }`. Keep the newest 5 (spec 3.1). `resolve` uses `URL(resolvingBookmarkData:)` and returns the new path if the folder moved.

- [ ] **Step 1: Write the failing tests**: save then load gives an equal session; `delete` removes the folder; the 6th `remember` drops the oldest; remembering the same path again moves it to the top and does not duplicate it; `resolve` after a folder rename returns the new path.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add session storage and recent folders`.

---

## Phase 2: Classify and review logic

### Task 8: Clustering and proposed categories

**Files:**
- Create: `Services/Clustering.swift`, `Services/ScanService.swift`, tests for both

**Interfaces:**
- Consumes: `MediaRepository`, `EmbeddingRepository`, `CandidateRepository`, `SessionRepository`, `VectorMath`.
- Produces:
  - `enum Clustering { static func kMeans(_ v: [Vector], k: Int, seed: UInt64) -> [Int]; static func silhouette(_ v: [Vector], labels: [Int], sampleLimit: Int, seed: UInt64) -> Float; static func bestK(_ v: [Vector], range: ClosedRange<Int>, seed: UInt64) -> (k: Int, labels: [Int]) }`. Cosine distance. k-means++ start, at most 50 iterations. `silhouette` uses at most `sampleLimit` (2000) random points. `bestK` uses `6...14`, limited to `count - 1`, and returns 1 cluster if there are fewer than 7 photos.
  - `enum ScanEvent: Sendable { case preparingModel, embedding(done: Int, total: Int), finished(Session) }`
  - `final class ScanService: Sendable { func firstScan(source: URL, list: CandidateList) -> AsyncThrowingStream<ScanEvent, Error>; func rescan(_ s: Session, source: URL) -> AsyncThrowingStream<ScanEvent, Error> }`. Task 10 adds the rescan rules. Both streams save the session at the end. Task 9 adds the call to `ClassifyService.classify` before the save. In Task 8, the first scan gives each image `.auto` of its cluster's category with `percent: 0, uncertain: false`.

- [ ] **Step 1: Write the failing tests**:
  - `kMeansSeparatesThreeBlobs`: 3 groups of 20 vectors around 3 axes → 3 clean groups.
  - `bestKFindsSixOnSixBlobs`: 6 well-separated groups → `k == 6`.
  - `firstScanNamesClustersFromCandidates`: `FakeEmbedder` maps image vectors near the text vectors of "Food" and "Pets" prompts → 2 categories named `Food` and `Pets`, with their emoji and prompts, `order` 0 and 1.
  - `duplicateCandidateGetsSuffix`: 2 clusters near "Food" → `Food` and `Food 2`.
  - `firstScanWithNoPhotos`: empty folder → session with 0 categories, no crash.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Name each cluster with the candidate whose best prompt has the highest cosine with the normalized cluster center (spec 4.3). Make a `Category` for each cluster. Videos get no embedding. Unreadable photos get `.unreadable`.
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add clustering and proposed categories`.

### Task 9: Classify service

**Files:**
- Create: `Services/ClassifyService.swift`, `Tests/.../ClassifyServiceTests.swift`

**Interfaces:**
- Consumes: `VectorMath`, `ClassifySettings`, `Category`, `PhotoState`.
- Produces: `struct ClassifyService { let settings: ClassifySettings; func classify(states: [MediaID: PhotoState], categories: [Category], images: [MediaID: Vector], prompts: [CategoryID: [Vector]]) -> [MediaID: PhotoState] }`. It changes only `.auto` states and media with no state. It keeps `.manual`, `.heldNotSure`, `.dontMove`, and `.unreadable`. Examples are the image vectors of `category.exampleIDs`.

Score rule (spec 4.4–4.6, constants from Task 4):

```
promptScore(c)  = max cosine(photo, p) for p in prompts[c]
exampleScore(c) = mean of the 3 highest cosine(photo, e) for e in examples(c), excluding the photo itself
score(c)        = max(promptScore(c), exampleScale * exampleScore(c) + exampleOffset)   // only the first term if c has no examples
uncertain       = best < minScore || best - second < minMargin
percent         = Int((softmax(all scores, temperature)[best] * 100).rounded())
```

- [ ] **Step 1: Write the failing tests**:
  - `picksBestPrompt`, `uncertainWhenLowScore`, `uncertainWhenMarginSmall` with exact values: settings `minScore 0.22, minMargin 0.02`; scores 0.30/0.29 → uncertain; 0.30/0.20 → certain; 0.21/0.10 → uncertain.
  - `manualStatesNeverChange`: a `.manual(catB)` photo whose best score is catA → still `.manual(catB)`. Same for `.heldNotSure`, `.dontMove`, `.unreadable`.
  - `examplesPullSimilarPhotos`: a photo with a low prompt score for catA but close to 3 example photos of catA → assigned to catA.
  - `photoIsNotItsOwnExample`.
  - `noCategories`: 0 categories → all auto photos stay without assignment (state removed), no crash.
  - `recalculationIsFast`: 5,000 random photos, 10 categories, 500 examples → `classify` finishes in under 2 seconds in a release build (`swift test -c release --filter recalculationIsFast`). Spec 4.7.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** with `VectorMath.matmul` for prompts and examples (1 matrix multiply each, not loops of `dot`).
- [ ] **Step 4: Wire `ClassifyService` into `ScanService`.** Call `classify` before the session save in `firstScan`. Update the Task 8 test `firstScanNamesClustersFromCandidates` to expect real `percent` values.
- [ ] **Step 5: Run them**, then the release performance test. Expected: PASS.
- [ ] **Step 6: Commit** `feat(macos): add classify service`.

### Task 10: Review service and rescan

**Files:**
- Create: `Services/ReviewService.swift`, `Tests/.../ReviewServiceTests.swift`
- Modify: `Services/ScanService.swift` (rescan), `Tests/.../ScanServiceTests.swift`

**Interfaces:**
- Consumes: `ClassifyService`, `SessionRepository`, `EmbeddingRepository`.
- Produces: `@MainActor final class ReviewService` (it owns the open session; the view model observes it):
  - `private(set) var session: Session`
  - `func move(_ ids: [MediaID], to c: CategoryID)` → `.manual(c)`, add ids to `exampleIDs` of `c`, remove them from other categories' `exampleIDs`.
  - `func acceptBestGuess(_ ids: [MediaID])` → `.manual(bestCategory)` for each not-sure id. Other ids are ignored.
  - `func acceptAllNotSure()`, `func acceptGroup(bestCategory: CategoryID)`
  - `func dontMove(_ ids: [MediaID])`
  - `func addCategory(name: String, emoji: String) -> CategoryID` → prompt `"a photo of <name>"` (spec 4.4), `order` at the end.
  - `func rename(_ c: CategoryID, to name: String)`, `func setEmoji(_ c: CategoryID, _ e: String)`, `func reorder(_ ids: [CategoryID])`
  - `func merge(_ from: CategoryID, into: CategoryID)` → `.manual(from)` → `.manual(into)`; examples move; `from` is removed; `.auto` photos are classified again.
  - `func delete(_ c: CategoryID)` → all photos of `c` (manual and auto) become `.heldNotSure(<new assignment>)`; examples are dropped.
  - `func undo()`, `func redo()`, `var canUndo: Bool`, `var canRedo: Bool` — snapshot undo: each action pushes `ReviewChange(categories: [Category], states: [MediaID: PhotoState])` (add `ReviewChange` to `Domain/Session.swift`). Stack limit 100.
  - `var notSureGroups: [(category: CategoryID, ids: [MediaID])]` — grouped by best guess, largest first (spec 3.4).
  - `func counts() -> (all: Int, notSure: Int, changedByYou: Int, perCategory: [CategoryID: Int], dontMove: Int, videos: Int, unreadable: Int)`
  - Each action runs `ClassifyService.classify` on a background task, then publishes the new states, then saves the session.

- [ ] **Step 1: Write the failing tests** for each action above. Must include:
  - `moveMakesManualAndExample`
  - `deleteHoldsPhotosInNotSureEvenIfConfident` (a confident photo stays `.heldNotSure`)
  - `mergeKeepsManualPicks`
  - `undoRestoresStatesAndCategories` and `redoAfterUndo`
  - `acceptAllEmptiesNotSure`
  - `rescanKeepsCategoriesAndManualPicks`: rename a category, make a manual pick, add 1 new file and remove 1 manual-pick file, rescan → names and other manual picks are the same, new file has a state, removed file is not in the session and not in any `exampleIDs` (spec 5.1).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** `ReviewService` and `ScanService.rescan`. Rescan never calls `Clustering`.
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add review actions and rescan`.

---

## Phase 3: Sort and undo

### Task 11: Sort planner

**Files:**
- Create: `Services/SortPlanner.swift`, `Tests/.../SortPlannerTests.swift`

**Interfaces:**
- Consumes: `Session`, `SortOptions`.
- Produces:
  - `struct SortPlan { entries: [PlanEntry]; folderCounts: [(folder: String, count: Int)]; leftInSource: Int }`
  - `enum SortPlanError: Error, Equatable { case destinationIsSource, destinationInsideSource, categoryFolderInsideSource }` (final review I2 and M5)
  - `struct SortPlanner { func plan(_ s: Session, source: URL, options: SortOptions, existingNames: (URL) -> Set<String>) throws -> SortPlan; static func folderName(for displayName: String) -> String }`. `existingNames` lists file names already in a destination folder, so the planner can avoid collisions without file access in tests.

Rules (spec 7): `.manual(c)` and certain `.auto` → folder of `c`. Not-sure photos → by `notSureChoice`: best category folder, `Not sure/`, or no entry. `.dontMove` → no entry. Videos → `Videos/`. `.unreadable` → `Unreadable/` with the original name. With `dateFolders`, add `YYYY-MM/` (local time) below each folder. With `rename`, name `YYYY-MM-DD_NNN.<ext>`; number photos in the order (date, original name) for each (date, folder).

- [ ] **Step 1: Write the failing tests**:
  - `noDateFoldersByDefault`: a photo in `Food` → destination `<dest>/Food/IMG_1.jpg`.
  - `dateFoldersWhenTicked` → `<dest>/Food/2024-05/IMG_1.jpg`.
  - `renameFormat`: 2 photos on 2024-05-12, `a.JPEG` and `b.jpg` → `2024-05-12_001.jpg`, `2024-05-12_002.jpg`.
  - `collisionAddsSuffix`: 2 photos named `a.jpg` from different subfolders → `a.jpg`, `a 2.jpg`; with `existingNames` holding `a.jpg` → `a 2.jpg`, `a 3.jpg`.
  - `notSureChoices`: each of the 3 choices gives the expected folder or no entry, and `leftInSource` counts it.
  - `dontMoveStays`, `videosAndUnreadable`.
  - `folderNames` (Review Focus 4): `"A/B:C"` → `"A-B-C"`; `".hidden"` → `"-hidden"`; `"   "` → `"Untitled"`; 2 categories `"A/B"` and `"A:B"` → `"A-B"` and `"A-B 2"`.
  - `refusesSourceAsDestination` (Review Focus 3): `destination == source` → `.destinationIsSource`. Any destination inside the source → `.destinationInsideSource`. The default `<source> - sorted` is next to the source and is accepted.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add sort planner`.

### Task 12: Sort, journal, undo

**Files:**
- Create: `Repositories/JournalRepository.swift`, `Repositories/FileOps.swift`, `Services/SortService.swift`, tests

**Interfaces:**
- Consumes: `SortPlan` (Task 11), `SessionRepository.directory(for:)` (Task 7).
- Produces:
  - `protocol FileOps: Sendable { func exists(_ u: URL) -> Bool; func makeFolder(_ u: URL) throws; func copy(_ from: URL, _ to: URL) throws; func size(_ u: URL) throws -> Int64; func modified(_ u: URL) throws -> Date; func remove(_ u: URL) throws; func isEmptyFolder(_ u: URL) -> Bool }` with `struct LocalFileOps: FileOps` (uses `FileManager.copyItem`, which keeps metadata). Tests use a `FailingFileOps` wrapper that throws on the Nth copy.
  - `struct JournalRepository { init(directory: URL); func append(_ e: JournalEntry) throws; func read() throws -> [JournalEntry]; func lastIsComplete() throws -> Bool?; func archive(suffix: String) throws }`. File `journal.jsonl`. `append` writes and flushes 1 line. `lastIsComplete` returns `nil` if no journal exists.
  - `enum SortError: Error, Equatable { case changedSinceScan([MediaID]), destinationExists([URL]), unfinishedLastSort, sizeMismatch(URL), stopped }`
  - `enum SortEvent: Sendable { case progress(done: Int, total: Int), finished(copied: Int, moved: Int) }`
  - `final class SortService: Sendable { func run(_ plan: SortPlan, mode: SortMode, journal: JournalRepository, stop: @Sendable () -> Bool) -> AsyncThrowingStream<SortEvent, Error>; func undo(journal: JournalRepository) throws }`

Rules: spec 7.3 steps 1–6. Before a new run: if `lastIsComplete() == false` → `.unfinishedLastSort`; if it is `true` → `archive(suffix: <timestamp>)`. Check every entry's size and modified date, and that no destination exists, before the first operation. Stop finishes the current file, does not write `done`, and throws `.stopped`. Undo: reverse order; `copy` → remove destination; `move` → copy back to source, then remove destination; `mkdir` → remove if empty; then `archive(suffix: "<timestamp>.undone")`.

- [ ] **Step 1: Write the failing tests** (real files in `TempDir`):
  - `copyThenUndoRestoresBothFolders`: snapshot (relative path → size) of source and destination before; run copy; undo; snapshot equal; destination folder is gone.
  - `moveThenUndoRestoresBothFolders`: same with move; source files have the same bytes after undo.
  - `stopsIfFileChangedSinceScan` (Review Focus 2): change 1 file's size after planning → `.changedSinceScan`, no destination folder made.
  - `stopsIfFileRemovedSinceScan` (Review Focus 2) → `.changedSinceScan`.
  - `failedCopyCanBeUndone` (Review Focus 2, disk full): `FailingFileOps` throws on copy 3 of 5 → the stream throws, journal has 2 copies and no `done`, `undo` leaves the destination empty.
  - `refusesNewSortAfterUnfinishedSort` (Review Focus 5): a journal with no `done` → `.unfinishedLastSort`.
  - `sizeMismatchKeepsSource` (move): `FileOps` that reports a wrong copy size → `.sizeMismatch`, source still exists.
  - `stopWritesNoDone`: stop after 2 files → `.stopped`, `lastIsComplete() == false`, undo works.
  - `vietnameseNamesSortAndUndo` (Review Focus 1): source `hình ảnh/ảnh 1.jpg` in NFD → copy and undo succeed.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add sort, journal, and undo`.

---

## Phase 4: App shell

### Task 13: Xcode project, composition, Welcome screen

**Files:**
- Create: `project.yml`, `Picnest.xcodeproj` (generated), `Picnest/App/*`, `Picnest/Welcome/*`, `Picnest/Assets.xcassets`, `PicnestTests/WelcomeViewModelTests.swift`

**Interfaces:**
- Consumes: all Core services and repositories.
- Produces:
  - `@MainActor final class AppEnvironment` — makes every repository and service 1 time (`CoreMLEmbedder` with the size from Task 4 and `Bundle.main.resourceURL/Models`). Tests make it with fakes: `init(embedder: any Embedder, sessionsRoot: URL, defaults: UserDefaults)`.
  - `@MainActor @Observable final class AppModel { enum Screen { case welcome, scanning(URL), review(ReviewService) } var screen: Screen; func open(_ url: URL); func finishScan(_ s: Session) }`. `open` loads an existing session and goes to `.review`, or starts `.scanning`.
  - `@MainActor @Observable final class WelcomeViewModel { var recent: [RecentFolder]; var candidateList: CandidateList; func choose(_ url: URL); func openRecent(_ f: RecentFolder) }`. `choose` calls `BookmarkRepository.remember`. `openRecent` uses `resolve`; if it returns `nil`, the view shows "Folder not found" and a **Find Folder…** button (spec 9).

- [ ] **Step 1: Write `project.yml`.** App target `Picnest` (macOS 15.0, bundle id `dev.megabuild.picnest`, product name `Picnest`, hardened runtime, no sandbox, `CODE_SIGN_IDENTITY = "-"` by default so it builds with no team), local package dependency `PicnestCore`, a pre-build script that fails with "Run scripts/fetch-models.sh" if `Models/` has no `.mlpackage`, and a copy-files phase that copies `Models/` to `Resources/Models`. Test target `PicnestTests`.
- [ ] **Step 2: Run** `brew install xcodegen` (if missing) `&& cd macos && xcodegen generate`. Expected: `Picnest.xcodeproj` exists.
- [ ] **Step 3: Write the failing `WelcomeViewModelTests`**: `choose` with a folder that has a saved session → `AppModel.screen` is `.review`; with a new folder → `.scanning`; `recent` shows at most 5 items from `BookmarkRepository`.
- [ ] **Step 4: Run** `xcodebuild test -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS'`. Expected: FAIL.
- [ ] **Step 5: Implement** `PicnestApp` (`WindowGroup`, `.defaultSize(width: 1200, height: 800)`, `.windowResizability(.contentMinSize)` with min 1000 × 680), `AppEnvironment`, `AppModel`, `WelcomeViewModel`, and `WelcomeView` (spec 3.1: drop zone with `.dropDestination(for: URL.self)` that accepts folders only, **Choose Folder…** with `.fileImporter(allowedContentTypes: [.folder])`, recent list, the privacy line, a small candidate list menu with "Everyday" and "Art studio" (spec 4.3)). Add `AccentColor` `#C8557A` with a dark variant.
- [ ] **Step 6: Run the tests and build.** Expected: PASS, build succeeds.
- [ ] **Step 7: Commit** `feat(macos): add app project and welcome screen`.

### Task 14: Scan screen

**Files:**
- Create: `Picnest/Scan/ScanView.swift`, `Picnest/Scan/ScanViewModel.swift`, `PicnestTests/ScanViewModelTests.swift`

**Interfaces:**
- Consumes: `ScanService.firstScan` / `rescan` (Tasks 8, 10), `AppModel` (Task 13).
- Produces: `@MainActor @Observable final class ScanViewModel { var phase: Phase /* .preparingModel, .embedding(done:total:), .failed(String) */; var etaText: String?; func start(); func cancel() }`.

- [ ] **Step 1: Write the failing tests** with a `FakeEmbedder` and 10 test images: events change `phase` in order; `finished` calls `AppModel.finishScan`; `cancel` returns to the Welcome screen and a second `start` makes fewer embed calls.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Copy the text from spec 3.2 ("Preparing the model…", `1,240 / 2,413` with a grouping separator). Estimate the time left from the mean time for each photo over the last 64 photos. If `finished` has 0 photos, show "No photos found in this folder." and a **Choose Another Folder** button. If the scan fails with a permission error (macOS privacy prompt denied, spec 12 risk 4), show "Picnest cannot open this folder." and a button **Open System Settings** that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders`. Add a test for this case with a `MediaRepository` stub that throws `CocoaError(.fileReadNoPermission)`.
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add scan screen`.

### Task 15: Review screen layout

**Files:**
- Create: `Picnest/Review/ReviewView.swift`, `ReviewViewModel.swift`, `SidebarView.swift`, `PhotoGridView.swift`, `PhotoTile.swift`, `QuickLookPreview.swift`, `PicnestTests/ReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `ReviewService` (Task 10), `ImageRepository` (Task 6).
- Produces: `@MainActor @Observable final class ReviewViewModel`:
  - `enum SidebarItem: Hashable { case all, notSure, changedByYou, category(CategoryID), dontMove, videos, unreadable }`
  - `var selectedItem: SidebarItem`, `var sortOrder: SortOrder /* .lowestConfidence, .date, .name */`, `var columns: Int /* 2...8, default 3 */`
  - `var visibleIDs: [MediaID]` — the photos of `selectedItem` in `sortOrder`.
  - `func tile(_ id: MediaID) -> TileModel` with `TileModel { name: String; secondLine: String; badge: Badge /* .percent(Int, isUncertain: Bool), .you */ }`. Second line: date (`"no date"` for `.modificationTime`) in category views, `"or <name> <n>%"` in "Not sure" (spec 3.3).
  - `func rescan()`

- [ ] **Step 1: Write the failing tests**: `visibleIDs` for each sidebar item; `lowestConfidence` order; tile badge `.you` for manual; second line `"no date"` for a modification-time date and `"or Documents 38%"` in "Not sure".
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** the view model and views. Layout from `docs/specs/assets/2026-10-21-macos-app/notsure-v3.html` panel B and spec 3.3: `NavigationSplitView`; sidebar sections Review / Categories / Other with counts; compact `.toolbar` with title, count chip, path, size slider, Rescan, **Sort Photos…** (`.borderedProminent`, opens Task 18 sheet; disabled until Task 18); `LazyVGrid` with `columns` flexible items; tiles load thumbnails with `.task(id:)` from `ImageRepository` at `maxPixel` = 2 × tile width; overlay with file name and second line on a dark gradient; badge top-left (green if not uncertain, amber if uncertain). Space and double-click open `QLPreviewPanel` for the selected photo.
- [ ] **Step 4: Run the tests and build.** Expected: PASS.
- [ ] **Step 5: Manual check:** run the app on a copy of 200 real photos. The sidebar counts add up to "All photos". Scrolling stays smooth at 8 columns. Light and dark mode both look right.
- [ ] **Step 6: Commit** `feat(macos): add review screen layout`.

---

## Phase 5: Review actions

### Task 16: Selection, moving, category edits, undo

**Files:**
- Create: `Picnest/Review/SelectionBar.swift`
- Modify: `ReviewViewModel.swift`, `SidebarView.swift`, `PhotoGridView.swift`, `ReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `ReviewService` actions (Task 10).
- Produces (on `ReviewViewModel`): `var selection: Set<MediaID>`; `func click(_ id: MediaID, modifiers: EventModifiers)`; `func selectAll()`; `func moveSelection(to: CategoryID)`; `func moveSelection(toKey n: Int)` (1–9 → category with `order == n-1`); `func acceptSelection()`; `func dontMoveSelection()`; `var canAcceptSelection: Bool`; `func drop(_ ids: [MediaID], on: CategoryID)`; `func undo()`; `func redo()`.

- [ ] **Step 1: Write the failing tests**: ⌘-click adds, ⇧-click selects the range in `visibleIDs`; key `2` moves to the second category; `canAcceptSelection` is false when no selected photo is not-sure; after `moveSelection` the selection is empty and the photos leave the "Not sure" list; `undo` puts them back.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Selection bar from spec 3.3 (count, **Accept Best Guess**, **Move to…** menu with number keys and **New Category…**, **Don't Move**, hint text). Tiles are `.draggable` with the media IDs; sidebar category rows are `.dropDestination` with a highlight. Keys `1`–`9` with `.onKeyPress`. Sidebar context menu: Rename, Change Icon (emoji picker: the system Character Viewer, or a text field limited to 1 emoji), Merge Into…, Delete with a confirmation dialog: "Delete <name>? Its <n> photos go to Not sure." Drag to reorder categories. ⌘Z / ⇧⌘Z through the Edit menu (`CommandGroup(replacing: .undoRedo)`).
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add review selection and actions`.

### Task 17: "Not sure" view

**Files:**
- Create: `Picnest/Review/NotSureView.swift`
- Modify: `ReviewView.swift`, `ReviewViewModel.swift`, `ReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `ReviewService.notSureGroups`, `acceptGroup`, `acceptAllNotSure` (Task 10).
- Produces (on `ReviewViewModel`): `var notSureGroups: [NotSureGroup]` with `NotSureGroup { categoryName: String; ids: [MediaID] }`; `func acceptGroup(at index: Int)`; `func selectGroup(at index: Int)`; `func acceptAll()`.

- [ ] **Step 1: Write the failing tests**: groups are largest first; `acceptGroup` empties that group and raises "Changed by you" by its size; `acceptAll` leaves "Not sure" empty; undo after `acceptAll` restores all groups.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** from `notsure-v3.html` panel A and spec 3.4: the amber notice line (exact text from spec 3.4), group headers "Best guess: <name>" with count, **Select All**, **Accept <N>**, and the toolbar button **Accept All Best Guesses** (shown only in this view).
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add Not sure view with batch accept`.

---

## Phase 6: Sort sheet and finish

### Task 18: Sort sheet

**Files:**
- Create: `Picnest/Sort/SortSheet.swift`, `Picnest/Sort/SortViewModel.swift`, `PicnestTests/SortViewModelTests.swift`
- Modify: `ReviewView.swift` (enable **Sort Photos…**)

**Interfaces:**
- Consumes: `SortPlanner` (Task 11), `SortService`, `JournalRepository` (Task 12).
- Produces: `@MainActor @Observable final class SortViewModel { var options: SortOptions; var plan: SortPlan?; var planError: SortPlanError?; var title: String; var previewLines: [String]; var showNotSureChoice: Bool; var sortButtonTitle: String; var state: State /* .editing, .confirmingMove, .running(done:total:), .finished(copied:moved:), .failed(String) */; func sort(); func confirmMove(); func stop() }`

- [ ] **Step 1: Write the failing tests**: `title == "Sort 2,401 photos into 7 folders"` for that plan; `sortButtonTitle` is `"Sort"` for copy and `"Move 2,401 Photos"` for move; `sort()` in move mode goes to `.confirmingMove` first; `showNotSureChoice` is false when no photo is not-sure; `previewLines` changes when `dateFolders` changes; `planError == .destinationIsSource` disables Sort; a `.unfinishedLastSort` error shows "The last sort did not finish. Click Undo Last Sort first."
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** from `sheet-v4.html` and spec 3.5: destination row with **Change…** (`.fileImporter` for a folder), Copy/Move cards, the 2 checkboxes, the 3 "Not sure" choices, the preview tree (first 3 folders with counts, then `…`), progress with **Stop**, and the summary with **Show in Finder** (`NSWorkspace.shared.activateFileViewerSelecting`) and **Done**. Make the plan again on each option change, off the main thread.
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): add sort sheet`.

### Task 19: After the sort, build guide, full run

**Files:**
- Create: `BUILD.md`
- Modify: `AppModel.swift`, `WelcomeView.swift`, `WelcomeViewModel.swift`, `ReviewView.swift`, `WelcomeViewModelTests.swift`, `docs/guides/classify-usage.md` (link to the app), `docs/specs/2026-10-21-macos-app-design.md` (record builder decisions, spec 14)

**Interfaces:**
- Consumes: `SortService.undo`, `SessionRepository.delete`, `BookmarkRepository.remember(_:photoCount:sortedAt:)`.
- Produces: `WelcomeViewModel.undoLastSort(_ f: RecentFolder)`; `AppModel.done()`; the reopen prompt.

- [ ] **Step 1: Write the failing tests** (spec 9.1): **Done** sets `session.sortedAt`, remembers the folder with `sortedAt`, and goes to Welcome; `undoLastSort` reverses the journal and clears `sortedAt`; opening a sorted folder asks "Start a new sort? The last sort can no longer be undone."; agreeing deletes the old session and starts a scan; the Review toolbar shows **Undo Last Sort** after a sort until **Done**.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Write `BUILD.md`** (spec 8, ASD-STE100 style, OKF frontmatter, `type: guide`, links to the spec): install Xcode, `brew install xcodegen`, run `scripts/fetch-models.sh`, open `Picnest.xcodeproj`, select "My Mac", click Run, copy `Picnest.app` from Products to `/Applications`, and what to do if macOS blocks the app (build again on that Mac). Add a link to it from `docs/guides/classify-usage.md`.
- [ ] **Step 6: Full manual run (spec 1.6, task exit check of spec 11 phase 6).** Copy 500 real photos from the Zalo folder to a temp folder. In the app: scan, rename 1 category, move 5 photos, accept 1 "Not sure" group, quit, open again (changes still there), sort with Copy, Undo Last Sort (both folders as before), sort with Move and date folders on, Undo Last Sort (both folders as before). Record the scan time for 500 photos.
- [ ] **Step 7: Record builder decisions** in spec 14: JSON session data, the Everyday list file, macOS 15.0, bundle id.
- [ ] **Step 8: Run all tests and the build, then commit** `feat(macos): finish sort flow and add build guide`.

---

## Phases 7–10: User feedback (2026-10-22)

### Additional Global Constraints (phases 7–10)

- Move to Trash uses `FileManager.trashItem(at:resultingItemURL:)` only. Never `removeItem` on a user photo outside the sort (spec 7.4).
- Only a user action moves a photo to the Trash. Duplicates are pre-marked, never trashed by the app alone (spec 4.9).
- New `Session` fields must decode from old `session.json` files that do not have them (`decodeIfPresent` with an empty default).
- Rename format `YYYY-MM-DD_<folder name>_NNN.<ext>`; unreadable files keep their names (spec 7.2).
- `duplicateSimilarity` default 0.95, in `ClassifySettings` (provisional, phase 0 tunes it).
- Suggestion minimum: 7 "Not sure" photos to suggest, 3 photos per suggestion. Sort-sheet hint: ≥ 20 "Not sure" photos and ≥ 10% of photos (spec 3.5, 4.8).
- Exact texts come from the spec sections named in each task. Do not invent new user-facing text where the spec gives one.

### Additional Review Focus (phases 7–10)

1. An old `session.json` (no `trashed`, no `notDuplicateKeys`) must open. Test in Task 22.
2. The Trash is emptied before ⌘Z, or a new file sits at the original path: undo keeps the photo trashed and shows the spec 7.4 message; no overwrite. Test in Task 22.
3. A volume with no Trash: `trashItem` throws; the photo stays and the spec 14 message shows; nothing is deleted. Test in Task 22 (fake `FileOps` that throws).
4. A duplicate group that contains a manual pick or the only example of a category: trashing it removes it from `exampleIDs` and reclassifies. Test in Task 26.
5. Trashed photos never appear in a sort plan, counts, groups, or suggestions. Tests in Tasks 22, 24, 26.

---

## Phase 7: Small feedback items

### Task 20: Recent folders and the reopen dialog

**Files:**
- Modify: `PicnestCore/Sources/PicnestCore/Services/LibraryService.swift`, `PicnestCore/Sources/PicnestCore/Repositories/BookmarkRepository.swift`, `Picnest/Welcome/WelcomeViewModel.swift`, `Picnest/Welcome/WelcomeView.swift`
- Test: `PicnestCore/Tests/PicnestCoreTests/LibraryServiceTests.swift`, `BookmarkRepositoryTests.swift`, `PicnestTests/WelcomeViewModelTests.swift`

**Interfaces:**
- Consumes: `BookmarkRepository.forget(id:)`, `LibraryService.isSorted`, `undoLastSort(_ f: RecentFolder)`, `startNewSort`, `canUndoLastSort`.
- Produces:
  - `BookmarkRepository.clear() throws`
  - `LibraryService.removeRecent(_ f: RecentFolder)`, `LibraryService.clearRecent()` — list entries only; sessions untouched.
  - `LibraryService.undoLastSort(source: URL) async throws` — same rules as `undoLastSort(_ f:)` (wait for idle, `.busy` retry once, clear `sortedAt`), for a folder that is not in the recent list. Refactor so both entry points share 1 private implementation.
  - `LibraryService.canUndoLastSort(source: URL) -> Bool` — false when the journal holds paths outside `source` (moved folder) or no undoable journal exists.
  - `WelcomeViewModel.removeRecent(_:)`, `clearRecent()`; `NewSortRequest` gains `canUndo: Bool` and `sortedText: String`; `WelcomeViewModel.undoFromDialog() async` (undo, then open the review).

- [ ] **Step 1: Write the failing tests:** `clearRemovesAllEntries`; `removeRecentKeepsSession` (session file still loads); `undoLastSortBySourceWithoutRecentEntry` (sort → remove from recent → undo by source → both folders byte-identical, `sortedAt == nil`); `canUndoLastSortBySourceIsFalseForMovedFolder`; app: `removeRecentAndClearRecent`, `reopenSortedFolderDialogOffersUndo` (dialog title "This folder was sorted on <medium date, en_US>." and `canUndo == true`), `undoFromDialogOpensReview`.
- [ ] **Step 2: Run them.** Expected: FAIL (missing members).
- [ ] **Step 3: Implement.** Welcome: right-click on a recent row → **Remove from Recent**; a **Clear Recent Folders** button after the list (hidden when the list is empty). Replace the old "Start a new sort?" alert with the spec 9.1 dialog: **Undo Last Sort** (hidden when `canUndo == false`), **Start a New Sort**, **Cancel**. Keep the existing "unfinished sort" message path unchanged.
- [ ] **Step 4: Run** core `swift test` and app `xcodebuild test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): remove recent folders and undo from the reopen dialog`.

### Task 21: Rename format, Return key, photo context menu

**Files:**
- Modify: `PicnestCore/Sources/PicnestCore/Services/SortPlanner.swift`, `Picnest/Sort/SortSheet.swift`, `Picnest/Review/PhotoGridView.swift`, `Picnest/Review/PhotoTile.swift` (or `SelectableTile`), `Picnest/Review/ReviewViewModel.swift`, `Picnest/Review/ReviewView.swift`
- Test: `SortPlannerTests.swift`, `PicnestTests/ReviewViewModelTests.swift`

**Interfaces:**
- Produces:
  - Rename name = `"\(day)_\(folderName)_\(number).\(ext)"` where `folderName` is the final folder name (after the ` 2` uniquing of spec 7.1) of the folder that gets the file, excluding any date sub-folder.
  - `ReviewViewModel.contextMenuSelect(_ id: MediaID)` — if `id` is not in `selection`, select only `id` (anchor = id).
  - `ReviewViewModel.openInDefaultApp()`, `showInFinder()` — call an injected `@MainActor (URL) -> Void` opener and `([URL]) -> Void` revealer (default `NSWorkspace`), so tests can assert URLs.
  - The Sort sheet label becomes "Rename files to date + category + number".

- [ ] **Step 1: Write the failing tests:** update `renameFormat` → `2024-05-12_Food_001.jpg`, `2024-05-12_Food_002.jpg`; `renameUsesUniquedFolderName` (categories "A/B" and "A:B" → `…_A-B_001.jpg` and `…_A-B 2_001.jpg`); `renameNotSureAndVideos` (`…_Not sure_001.jpg`, `…_Videos_001.mov`); `renameWithDateFolders` keeps the category (not `2024-05`) in the name; unreadable keeps the original name. App: `contextMenuSelectReplacesSelectionOnlyWhenOutside`, `openInDefaultAppUsesTheAnchor`, `showInFinderRevealsTheSelection`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Grid: `.onKeyPress(.return)` → `openPreview()` (same as Space). Tile `.contextMenu` (calls `contextMenuSelect` first): **Quick Look**, **Open**, **Show in Finder**, divider, **Move to…** submenu (categories + **New Category…**), **Accept Best Guess** (only if `canAcceptSelection`), **Don't Move**. (Task 23 adds **Move to Trash**.)
- [ ] **Step 4: Run** core and app tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): date + category rename, Return opens, photo context menu`.

---

## Phase 8: Move to Trash

### Task 22: Trash in the core

**Files:**
- Modify: `Repositories/FileOps.swift`, `Domain/Session.swift`, `Domain/Classification.swift` (no new `PhotoState` case), `Services/ReviewService.swift`, `Services/SortPlanner.swift`, `Services/ScanService.swift` (rescan), `Services/LibraryService.swift` (wiring)
- Create: `Services/TrashService.swift`
- Test: `TrashServiceTests.swift`, `ReviewServiceTests.swift`, `SortPlannerTests.swift`, `ScanServiceTests.swift`, `SessionRepositoryTests.swift`

**Interfaces:**
- Produces:
  - `FileOps.trash(_ u: URL) throws -> URL` (returns the Trash URL; `LocalFileOps` uses `trashItem(at:resultingItemURL:)`).
  - `struct TrashedPhoto: Codable, Sendable, Hashable { mediaID: MediaID; trashPath: String; time: Date }`; `Session.trashed: [TrashedPhoto]` (decodes as `[]` when absent).
  - `enum TrashError: Error, Equatable { case cannotTrash(MediaID, String), cannotPutBack(MediaID, String) }`.
  - `final class TrashService: Sendable { init(fileOps: any FileOps = LocalFileOps()); func trash(_ items: [(id: MediaID, url: URL)]) -> (done: [TrashedPhoto], failed: [TrashError]); func putBack(_ t: TrashedPhoto, to original: URL) -> TrashError? }` — `putBack` refuses if the Trash file is gone or a file exists at `original` (no overwrite).
  - `ReviewService.moveToTrash(_ ids: [MediaID]) async -> [TrashError]` — 1 undo step: removes ids from `states` and every `exampleIDs`, appends to `session.trashed`, reclassifies, saves. Undo of that step calls `putBack` for each item; items that fail stay trashed and are reported through `ReviewService.lastUndoErrors: [TrashError]` (observable). `ReviewChange` gains `trashedIDs: [MediaID]` for this.
  - `ReviewService.counts()`, `notSureGroups`, `visible` media: exclude trashed ids. `SortPlanner.plan` skips media in `session.trashed`.
  - Rescan: drop a `TrashedPhoto` whose original path does not exist; a trashed photo found again at its original path becomes a new photo (remove it from `trashed`).

- [ ] **Step 1: Write the failing tests:** `trashMovesFileAndRecordsIt` (real temp file; file gone from source, exists at returned URL; clean up the Trash entry in teardown); `undoPutsTrashedPhotoBack` (bytes identical); `undoAfterTrashEmptiedKeepsTrashed` (Review Focus 2); `undoRefusesWhenOriginalPathTaken` (Review Focus 2); `trashFailureKeepsPhoto` (fake FileOps throws → photo still in states, error returned; Review Focus 3); `trashedPhotoNotInPlanCountsOrGroups` (Review Focus 5); `trashingAnExampleReclassifies`; `oldSessionWithoutTrashedDecodes` (Review Focus 1: JSON without the key); `rescanDropsTrashedWithMissingOriginal`, `rescanRestoresPutBackPhoto`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Tests that touch the real Trash must use files under `TempDir` and remove their own Trash entries afterwards.
- [ ] **Step 4: Run** `swift test --package-path PicnestCore`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): move photos to the Trash with undo`.

### Task 23: Move to Trash in the app

**Files:**
- Modify: `Picnest/Review/ReviewViewModel.swift`, `SelectionBar.swift`, `PhotoGridView.swift`/tile context menu, `ReviewView.swift`, `Picnest/App/AppEnvironment.swift` (one `TrashService`)
- Test: `PicnestTests/ReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `ReviewService.moveToTrash`, `lastUndoErrors`.
- Produces: `ReviewViewModel.trashSelection() async`, `trashMessage: String?` (spec 7.4 / spec 14 texts: "The photo could not be moved to the Trash: <reason>." and "The photo could not be put back: <reason>.").

- [ ] **Step 1: Write the failing tests:** `trashSelectionRemovesPhotosAndClearsSelection`; `undoAfterTrashRestoresPhotos`; `trashFailureShowsMessage`; `putBackFailureShowsMessage`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Add **Move to Trash** to the tile context menu (last item, after a divider) and to the selection bar; ⌘⌫ on the focused grid (`.onKeyPress(.delete, modifiers: .command)` or a menu command scoped to the review). No confirmation.
- [ ] **Step 4: Run** app tests and the build. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): Move to Trash in the review screen`.

---

## Phase 9: Suggested categories

### Task 24: Suggestion rules in the core

**Files:**
- Create: `Services/SuggestionService.swift`, `Domain/Suggestion.swift`
- Modify: `Services/ReviewService.swift`, `Services/Clustering.swift` (reuse only; no copy of the k-range or k-means code)
- Test: `SuggestionServiceTests.swift`, `ReviewServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct CategorySuggestion: Sendable, Hashable, Identifiable { id: UUID; name: String; emoji: String; prompts: [String]; ids: [MediaID] }`
  - `struct SuggestionService: Sendable { func suggest(notSure: [MediaID: Vector], candidates: [Candidate], candidateVectors: [[Vector]], existingNames: Set<String>, settings: ClassifySettings, seed: UInt64) -> [CategorySuggestion] }` — spec 4.8 steps 1–6 exactly; reuses `Clustering.kRange(for:)` and `Clustering.bestK`; the cluster-center helper is shared with `ScanService` (extract it once if `ScanService` still has its own copy).
  - `ReviewService.suggestCategories() async throws -> [CategorySuggestion]` — loads candidate vectors through the embedding repository it already holds.
  - `ReviewService.addSuggested(_ s: [CategorySuggestion])` — 1 undo step: creates the categories at the end (order), moves their photos as manual picks (examples), recalc, save.

- [ ] **Step 1: Write the failing tests:** `fewerThan7NotSureSuggestsNothing`; `dropsClustersSmallerThan3`; `skipsCandidatesThatMatchExistingCategories` (case-insensitive) and uses the next best; `mergesClustersWithTheSameCandidate`; `lowScoreClusterIsNamedGroupN` (emoji 📁, prompt empty until named; on add, prompt "a photo of <name>"); `sortedBySizeLargestFirst`; `addSuggestedIsOneUndoStep` (undo removes categories and restores states); `trashedPhotosAreNotSuggested` (Review Focus 5).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** core tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): suggest categories for Not sure photos`.

### Task 25: Suggest Categories sheet and Sort sheet hint

**Files:**
- Create: `Picnest/Review/SuggestSheet.swift`, `Picnest/Review/SuggestViewModel.swift`
- Modify: `NotSureView.swift`/`ReviewView.swift` (toolbar button), `Picnest/Sort/SortViewModel.swift`, `SortSheet.swift`, `ReviewViewModel.swift`
- Test: `PicnestTests/SuggestViewModelTests.swift`, `SortViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class SuggestViewModel { var rows: [Row] /* suggestion + isOn + editable name/emoji */; var state: State /* .loading, .ready, .empty, .failed(String) */; var addTitle: String /* "Add <N> Categories" */; func load() async; func add() }`; `ReviewViewModel.canSuggest: Bool` (Not sure count ≥ 7); `SortViewModel.showSuggestHint: Bool`, `suggestHintText` ("<N> photos are not sure."), `func suggestFromSort()` (closes the sheet, selects `.notSure`, opens the suggest sheet).

- [ ] **Step 1: Write the failing tests:** rows default on; renaming and toggling change what `add()` creates; `addTitle` counts checked rows; empty state text from spec 3.7; Sort hint shown at 20 not-sure / 10% and hidden at 19 or 9%; `suggestFromSort` navigates.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** the sheet per spec 3.7 (row: check box, emoji field reusing `ReviewViewModel.isSingleEmoji`, name field, count, 4 thumbnails via `ThumbnailService`).
- [ ] **Step 4: Run** app tests and the build. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): Suggest Categories sheet and Sort hint`.

---

## Phase 10: Duplicates

### Task 26: Duplicate rules in the core

**Files:**
- Create: `Repositories/HashRepository.swift`, `Services/DuplicateService.swift`, `Domain/Duplicate.swift`
- Modify: `Repositories/ImageRepository.swift` (pixel size), `Domain/Classification.swift` (`ClassifySettings.duplicateSimilarity`, default 0.95, decodes when absent), `Domain/Session.swift` (`notDuplicateKeys: Set<String>`, decodes when absent), `Services/ReviewService.swift`
- Test: `HashRepositoryTests.swift`, `DuplicateServiceTests.swift`, `ReviewServiceTests.swift`

**Interfaces:**
- Produces:
  - `actor HashRepository { init(cacheDirectory: URL); func hashes(for media: [MediaFile], source: URL) async throws -> [MediaID: String] }` — SHA-256 (CryptoKit, streamed in 1 MB chunks) only for files whose size is shared with another file; cache file `hashes.json` keyed by the spec 4.2 key.
  - `ImageRepository.pixelSize(for url: URL) -> (width: Int, height: Int)?` (ImageIO properties, no decode).
  - `struct DuplicateGroup: Sendable, Hashable, Identifiable { enum Kind { case exact, similar }; kind; ids: [MediaID]; keepIDs: Set<MediaID>; var id: String /* sorted ids joined */ }`
  - `struct DuplicateService: Sendable { func groups(media: [MediaFile], hashes: [MediaID: String], vectors: [MediaID: Vector], pixels: [MediaID: Int], dates: [MediaID: Date], similarity: Float, dismissed: Set<String>) -> [DuplicateGroup] }` — spec 4.9 and spec 14 rules (exact first; similar search uses 1 Keep photo per exact group; union-find; blocked matmul of 1,000; best photo order; dismissed keys hidden).
  - `ReviewService.findDuplicates(progress:) async throws -> [DuplicateGroup]`, `dismissDuplicates(_ g: DuplicateGroup)` (saves the key), `cleanUp(_ groups: [DuplicateGroup]) async -> [TrashError]` (trashes ids not in `keepIDs` through `moveToTrash`, 1 undo step).

- [ ] **Step 1: Write the failing tests:** `hashesOnlySharedSizes`; `hashCacheReused`; `exactGroupFromSameBytes` (2 copies of 1 JPEG + 1 other); `similarGroupAboveThreshold` (vectors 0.97 grouped, 0.90 not); `chainJoinsIntoOneGroup` (A~B, B~C); `exactGroupNotRepeatedAsSimilar`; `bestPhotoOrder` (pixels, then size, then date, then path); `atLeastOneKeep`; `dismissedGroupHidden` and shown again when its ids change; `cleanUpTrashesNonKeepAndIsOneUndoStep`; `cleanUpRemovesExampleAndReclassifies` (Review Focus 4); `videosAndUnreadableNotGrouped`; `trashedPhotosNotGrouped` (Review Focus 5); `tenThousandVectorsUnder10Seconds` (release only, like `recalculationIsFast`).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** core tests and the release performance test. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): find exact and similar duplicates`.

### Task 27: Duplicates view

**Files:**
- Create: `Picnest/Review/DuplicatesView.swift`, `Picnest/Review/DuplicatesViewModel.swift`
- Modify: `SidebarView.swift` (Tools section), `ReviewViewModel.swift` (`SidebarItem.duplicates`), `ReviewView.swift`
- Test: `PicnestTests/DuplicatesViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class DuplicatesViewModel { var kind: DuplicateGroup.Kind; var groups: [DuplicateGroup] /* of kind */; var state: State /* .idle, .finding(done:total:), .ready, .empty */; var exactCount: Int; var similarCount: Int; var cleanUpTitle: String /* "Clean Up All" + count */; var cleanUpConfirmation: String; func find() async; func toggleKeep(_ id: MediaID, in g: DuplicateGroup); func trash(_ g: DuplicateGroup) async; func notDuplicates(_ g: DuplicateGroup); func cleanUpAll() async }`; sidebar count = photos that a clean-up would trash (0 until found).

- [ ] **Step 1: Write the failing tests:** `findsOnFirstOpenOnly` (second open reuses results until a rescan); `toggleKeepNeverLeavesZeroKeep`; `trashGroupUsesKeep`; `notDuplicatesHidesGroup`; `cleanUpConfirmationText` (spec 3.6 exact text with N); `emptyStateText` ("No duplicates found."); `segmentsCountGroups`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** per spec 3.6 and the reference look (section 6.1): segmented control, 1 card per group with side-by-side tiles (file name, pixel size, file size, **Keep** badge), card buttons **Move <N> to Trash** / **Not Duplicates**, toolbar **Clean Up All** with confirmation, Space/Return/double-click Quick Look, progress while finding.
- [ ] **Step 4: Run** app tests, core tests, and the build. Launch the app briefly (no crash). Add a `#Preview` with 1 exact and 1 similar group.
- [ ] **Step 5: Commit** `feat(macos): Duplicates view`.

---

## Phase 11: Start over and suggestions after a scan (feedback 2026-10-23)

Spec: R16–R18, sections 3.3 (**Start Over…**), 3.7, 5.1, 14. Main feature branch: `feature/start-over/main`.

### Additional Global Constraints (phase 11)

- 1 rule decides "many Not sure photos": at least 20 "Not sure" photos and at least 10% of the non-trashed images. It lives in the core. `SortViewModel` and the after-scan path both call it. No copy of the numbers in the app.
- **Start Over…** never deletes the embedding cache or `hashes.json`, and never touches photo files.
- Exact texts come from spec 3.3 (**Start Over…**). The unfinished-sort message is the existing `SortMessages.text(for: SortError.unfinishedLastSort)`.

### Additional Review Focus (phase 11)

1. A saved session with 0 categories and media (the user's real case): Rescan proposes categories and every readable image gets a state. Test in Task 28.
2. **Start Over…** after an unfinished sort: nothing is deleted and the message shows. Tests in Tasks 28 and 29.
3. **Start Over…** on a sorted folder: the journal is archived, so **Undo Last Sort** no longer shows for the folder. Test in Task 28.
4. The suggest sheet opens once after a scan, never after a plain reopen of a saved session. Test in Task 29.

### Task 28: Core: rescan repair, Start Over, the Not sure rule

**Files:**
- Modify: `Services/ScanService.swift`, `Services/LibraryService.swift`, `Repositories/SessionRepository.swift`, `Services/SuggestionService.swift`, `Services/ReviewService.swift`
- Test: `ScanServiceTests.swift`, `LibraryServiceTests.swift`, `SuggestionServiceTests.swift`, `ReviewServiceTests.swift`

**Interfaces:**
- Produces:
  - `SessionRepository.deleteSessionFile(source: URL) throws`: removes only `session.json`; no error if it is missing.
  - `LibraryService.startOver(_ url: URL) async throws`: `await sortService.waitUntilIdle()`, then `checkLastSortFinished(url)` (throws, deletes nothing), then archives the journal if it exists (`journal(for:).archive(suffix: "<timestamp>.startover")`), deletes the session file, and calls `remember(url, photoCount: <old count or 0>, sortedAt: nil)`.
  - `SuggestionService.manyNotSure(notSure: Int, images: Int) -> Bool` (static): `notSure >= 20 && notSure * 10 >= images`.
  - `ReviewService.hasManyNotSure: Bool`: the rule over the non-trashed images of the session.
  - `ScanService.rescan`: when `old.categories.isEmpty`, it proposes categories from the kept, readable, non-trashed images, as `runFirstScan` does. "Don't move" states stay. Share 1 helper between the first scan and this path; no copy of the proposal-to-states code.

- [ ] **Step 1: Write the failing tests:** `rescanOfSessionWithNoCategoriesProposesCategories` (fake embedder, 0 categories + 30 images → categories > 0, every readable image has a state, a Don't move photo keeps it); `rescanWithCategoriesStillNeverClusters` (existing behaviour kept); `startOverKeepsEmbeddingsAndHashes` (files still there, `session.json` gone); `startOverArchivesJournal` (`canUndoLastSort` false afterwards); `startOverRefusesUnfinishedSort` (journal without `done` → throws `SortError.unfinishedLastSort`, `session.json` still there); `manyNotSureRule` (20/200 true, 19/100 false, 20/201 false); `hasManyNotSureIgnoresTrashed`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** core tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(macos): repair sessions with no categories, add Start Over in the core`.

### Task 29: App: Start Over… command, suggestions after a scan

**Files:**
- Modify: `Picnest/App/AppModel.swift`, `App/RootView.swift`, `App/PicnestApp.swift`, `Review/ReviewCommands.swift`, `Review/ReviewView.swift`, `Review/ReviewViewModel.swift`, `Sort/SortViewModel.swift`
- Test: `PicnestTests/AppModelTests.swift`, `ReviewViewModelTests.swift`, `SortViewModelTests.swift`

**Interfaces:**
- Consumes: Task 28 (`LibraryService.startOver`, `ReviewService.hasManyNotSure`, `SuggestionService.manyNotSure`).
- Produces:
  - `AppModel.Screen.review(ReviewService, afterScan: Bool)`. `finishScan` opens review with `afterScan: true`; `open` of a saved session with `false`.
  - `AppModel.startOver() async throws`: waits for `review.settled()`, calls `library.startOver`, then shows `.scanning(source)` (a first scan). On a throw the screen stays on Review.
  - `ReviewViewModel`: `canStartOver: Bool` (same as `canSortOrRescan`); `isConfirmingStartOver: Bool`; `startOverMessage: String` (spec 3.3 text, plus the sorted sentence when `canUndoLastSort`); `func startOver() async` (shows the error text in an alert on a throw); `func suggestAfterScanIfNeeded()` (opens the suggest sheet once if `afterScan && review.hasManyNotSure`).
  - File menu item **Start Over…** (⇧⌘R) through the focused `review` value, disabled when `canStartOver` is false or no review is focused.
  - `SortViewModel.showSuggestHint` calls `SuggestionService.manyNotSure`.

- [ ] **Step 1: Write the failing tests:** `finishScanOpensReviewAfterScan` and `openSavedSessionIsNotAfterScan`; `suggestOpensOnceAfterScanWithManyNotSure`; `suggestDoesNotOpenOnReopen`; `suggestDoesNotOpenWithFewNotSure`; `startOverMessageAddsSortedSentence`; `startOverRunsFirstScan` (screen becomes `.scanning(url, rescanOf: nil)`); `startOverAfterUnfinishedSortShowsMessage` (screen stays Review); `startOverIsOffWhileFilesMove`; existing Sort hint tests still pass.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** The confirmation is a `.confirmationDialog` or `.alert` with the spec 3.3 title, text and buttons. `ReviewView` calls `suggestAfterScanIfNeeded()` in `.task`.
- [ ] **Step 4: Run** app tests, core tests, and the build. Run `xcodegen` and make sure git stays clean.
- [ ] **Step 5: Commit** `feat(macos): Start Over command and suggestions after a scan`.

---

## Phase 12: Automatic names (feedback 2026-10-23)

Spec: R19, sections 4.3, 4.8, 14. Main feature branch: `feature/auto-names/main`. The user said the code must name categories for any folder, with no manual step.

### Task 30: All topics list, names without "Group <n>", no list menu

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Resources/candidates-all.json`
- Modify: `Domain/Category.swift` (`CandidateList`), `Repositories/CandidateRepository.swift`, `Services/SuggestionService.swift`, `Services/ReviewService.swift` (suggestions load `.all`), `Picnest/Welcome/WelcomeView.swift`, `WelcomeViewModel.swift`, `App/AppModel.swift`, `Scan/ScanViewModel.swift`
- Test: `CandidateRepositoryTests.swift` (or the existing candidate tests), `SuggestionServiceTests.swift`, `ReviewServiceTests.swift`, app tests that use `candidateList`

**Interfaces:**
- Produces:
  - `CandidateList.all` (raw value `"all"`). Old raw values `everyday` and `artStudio` still decode, and ModelBench still loads them.
  - `candidates-all.json`: the 51 Everyday entries, the 40 Art studio entries, and at least 200 new common photo topics.
    - Topics: people, places, activities, objects, documents, events, nature, food types, art and craft, work, and Vietnamese life (Tet, markets, motorbikes).
    - Merge synonyms into 1 entry (for example "Selfie"/"Selfies", "Food"/"Food drink"). A merged or shortened entry keeps the old name in `aliases`.
    - Each entry: a display name of max 3 words, 1 emoji, and 1 to 3 English prompts ("a photo of …").
  - The first scan uses `.all`. `ReviewService.suggestCategories` uses `.all` for every session.
  - `SuggestionService.suggest`: the best allowed candidate always names the cluster, whatever its score. "Group <n>" only when no allowed candidate is left.
  - The Welcome screen has no list menu. `AppModel.candidateList` and the Welcome picker binding are removed.

- [x] **Step 1: Write the failing tests:**
  - `allListLoadsAndHasNoDuplicateNames` (≥ 291 entries, unique names, ≥ 1 prompt and 1 emoji each) and `allListContainsEverydayAndArtNamesOrSynonyms`.
  - `lowScoreClusterStillGetsCandidateName` (replaces `lowScoreClusterIsNamedGroupN`) and `groupNOnlyWhenNoCandidateLeft`.
  - `suggestionsUseAllListForOldSession`, `firstScanUsesAllList`, and an old `session.json` with `candidateList: "artStudio"` still decodes.
- [x] **Step 2: Run them.** Expected: FAIL.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run** core tests, app tests, the build, and `xcodegen` (git clean after a second run).
- [x] **Step 5: Commit** `feat(macos): name categories from one large topic list, no Group N`.

