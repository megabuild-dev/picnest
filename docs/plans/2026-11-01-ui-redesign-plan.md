---
id: picnest-ui-redesign-plan
title: Picnest UI Redesign Implementation Plan
type: plan
status: active
tags: [picnest, ui, theme, localization, swiftui, plan]
links:
  - "[[2026-11-01-ui-redesign-design]]"
  - "[[2026-10-21-macos-app-design]]"
  - "[[dictionary]]"
  - "[[BUILD]]"
  - "[[CONTRIBUTING]]"
---

# Picnest UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Picnest the approved UI, a System/Light/Dark appearance setting, and an English and Vietnamese interface.

**Architecture:** Add one token file for all colors and sizes. Add one appearance store and one language store, both with an injected `UserDefaults`. Move every UI string to one String Catalog. Then rebuild the window shell and each screen on the tokens. Layers stay: View, ViewModel, `PicnestCore` service, repository.

**Tech Stack:** Swift 6, SwiftUI, macOS 15, XcodeGen 2.46, `swift test` for `PicnestCore`, `xcodebuild test` for the app.

**Spec:** `docs/specs/2026-11-01-ui-redesign-design.md`. Mockups: `design/picnest-ui-01-library.png` to `design/picnest-ui-05-layout-editor.png`.

## Status (update after each task)

- [x] Phase 0: Foundation (tasks 0.1 to 0.7). Merged into `ui-redesign`. Manual checks A and B wait for the owner.
- [x] Phase 1: App shell (tasks 1.1 to 1.4). Merged into `ui-redesign`. Manual checks C and D wait for the owner.
- [ ] Phase 2: Screens (tasks 2.1 to 2.8)
- [ ] Phase 3: Favorites, Collections, Recently Deleted. Write a detailed plan after phase 2 (section "Later phases").
- [ ] Phase 4: Photo Editor. Same rule.
- [ ] Phase 5: Layout Editor. Same rule.

## Branches

Main branch: `ui-redesign`, from `main`. (Git cannot hold `feature/ui-redesign` and `feature/ui-redesign/...` together, so the main branch has no prefix, as `category-folders` has.). One sub-branch per phase: `feature/ui-redesign/phase-0-foundation`, `.../phase-1-shell`, `.../phase-2-screens`. Merge each sub-branch into the main branch when its tasks pass. Never merge into `main` before the owner approves.

## Global Constraints

- macOS 15, Swift 6 (`project.yml`: `SWIFT_VERSION: "6.0"`, `MACOSX_DEPLOYMENT_TARGET: "15.0"`).
- The default and source language is `en`. First added language is `vi`.
- Category names stay English data. CLIP prompts stay English. The UI does not translate them.
- The filter for photos the user decided is named **Chosen by you**.
- The sidebar is the full sidebar of mockups 01 and 02.
- A view uses no color literal. Colors come from `Theme`.
- A helper or ViewModel that gives text to a view returns `LocalizedStringKey` or `LocalizedStringResource`, never `String`.
- A task that adds or changes a UI string adds the `en` key and the `vi` value in the same commit.
- `PicnestCore` gets no String Catalog and no UI text.
- Body text contrast is at least 4.5:1 in light and dark.
- Minimum window is 1000 × 680. No text is cut at this size in `en` and `vi`.
- A screen change does not change a ViewModel or service rule. Write any rule change into this plan first.
- Commit messages have no `Co-Authored-By` line and no mention of Claude.
- After you add or remove a Swift file, run `xcodegen generate` and commit `Picnest.xcodeproj`.
- Test commands: `swift test --package-path PicnestCore` and `xcodebuild test -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS'`.
- Doc files follow OKF 2.0 and ASD-STE100 (sentences of 20 words or fewer).

## Review Focus

Each line has a test or a check in the named task.

1. A category name with Vietnamese letters (for example `Ẩm thực`, in NFC and NFD) makes a valid, unique folder name. Task 2.5.
2. `UserDefaults` holds an unknown appearance value or an unknown language value. The app falls back to `system`. Tasks 0.2 and 0.6.
3. A folder with 0 photos, and a filter with 0 results, show an empty state, not a blank area. Tasks 1.4 and 2.3.
4. A count of 0, 1, and 1,000 reads correctly in `en` and `vi` (plural variations). Task 0.5.
5. A selected tile and the confidence badge stay readable in dark mode on a very bright photo and a very dark photo. Task 2.3.

---

## Phase 0: Foundation

### Task 0.1: Design tokens

**Files:**
- Create: `Picnest/Design/Theme.swift`
- Create: `PicnestTests/ThemeTests.swift`
- Delete: `Picnest/Review/ReviewStyle.swift` (move its values)
- Modify: every file that uses `ReviewStyle` (`grep -rn ReviewStyle Picnest`)

**Interfaces:**
- Produces: `struct RGB: Equatable { let r, g, b: Double }` with `func contrast(with other: RGB) -> Double` (WCAG 2.x ratio).
- Produces: `struct ThemeColor { let light: RGB; let dark: RGB; var color: Color { get } }`. `color` is a dynamic `NSColor` that picks `dark` when the appearance is `.darkAqua`.
- Produces: `enum Theme` with static `ThemeColor` values: `background`, `sidebar`, `surface`, `textPrimary`, `textSecondary`, `accent`, `onAccent`, `confirmed` (green), `needsReview` (amber), `destructive` (red), `selection`.
- Produces: `enum Theme.Metrics` with `tileCorner: CGFloat = 10`, `gridSpacing: CGFloat = 12`, `sidebarMin: CGFloat = 220`, `sidebarMax: CGFloat = 250`.

- [ ] **Step 1: Write the failing tests** in `ThemeTests.swift`: `testBodyTextContrastInLightAndDark` (for `textPrimary`, `textSecondary` against `background`, `surface`, `sidebar`: ratio ≥ 4.5 in both modes), `testOnAccentContrastOnAccent` (≥ 4.5 in both modes), `testContrastOfBlackOnWhiteIs21` (`RGB(0,0,0).contrast(with: RGB(1,1,1))` within 0.01 of 21).
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/ThemeTests`. Expected: build fails (`Theme` not defined).
- [ ] **Step 3: Implement `Theme.swift`.** Read exact colors from the PNG files (use `sips -s format` + a pixel sample, or Preview's color picker): warm neutral background, charcoal text, berry/coral accent, green, amber, red. Keep the old green `#3A9A62` and amber `#C27A12` only if they pass the contrast tests. If white on the accent fails 4.5:1, darken the accent and write the new value in the commit message.
- [ ] **Step 4: Replace `ReviewStyle` uses** with `Theme`. Delete `ReviewStyle.swift`. Update `Picnest/Assets.xcassets/AccentColor.colorset` to the new accent so system controls match.
- [ ] **Step 5: Run the full app tests.** Expected: PASS.
- [ ] **Step 6: Commit** `feat(design): add theme tokens for light and dark`.

### Task 0.2: Appearance setting

**Files:**
- Create: `Picnest/Settings/AppearanceStore.swift`
- Create: `PicnestTests/AppearanceStoreTests.swift`

**Interfaces:**
- Produces: `enum AppearanceMode: String, CaseIterable, Identifiable { case system, light, dark }` with `var nsAppearance: NSAppearance? { get }` (`nil` for `system`).
- Produces: `@MainActor @Observable final class AppearanceStore { init(defaults: UserDefaults); var mode: AppearanceMode { get set } }`. Setting `mode` writes key `"appearance"` and sets `NSApp.appearance`. Method `applyCurrent()` applies the saved mode at launch.

- [ ] **Step 1: Write the failing tests:** `testDefaultIsSystem`, `testSetModeSavesAndReloads` (new store on the same suite reads `.dark`), `testUnknownRawValueFallsBackToSystem` (write `"sepia"` first), `testSystemHasNilAppearance`, `testLightAndDarkAppearanceNames` (`.aqua`, `.darkAqua`). Use `UserDefaults(suiteName:)` with a UUID name.
- [ ] **Step 2: Run them.** Expected: FAIL (types not defined).
- [ ] **Step 3: Implement** the types above in `AppearanceStore.swift`.
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Create the store in `AppEnvironment`** (it already takes `defaults: UserDefaults`) and call `applyCurrent()` in `AppDelegate.applicationDidFinishLaunching`. Read both files first.
- [ ] **Step 6: Commit** `feat(settings): add appearance store`.

### Task 0.3: Settings window with Appearance

**Files:**
- Create: `Picnest/Settings/SettingsView.swift`
- Modify: `Picnest/App/PicnestApp.swift` (add a `Settings { SettingsView(...) }` scene)

**Interfaces:**
- Consumes: `AppearanceStore` (task 0.2).
- Produces: `struct SettingsView: View` with `init(appearance: AppearanceStore)`. A `Picker` named "Appearance" with the 3 modes (labels **System**, **Light**, **Dark**).

- [ ] **Step 1: Implement** `SettingsView` and the scene. ⌘, opens it.
- [ ] **Step 2: Manual check A.** Run the app. Open Settings and a sheet (**Sort Photos…**). Switch Dark, System, Light, Dark. Every window changes at once, with no restart.
- [ ] **Step 3: If check A fails** (a window keeps the old look), compare `NSApp.appearance` with `preferredColorScheme` on the Settings scene. Keep the one that passes. Write the result in the commit message.
- [ ] **Step 4: Commit** `feat(settings): add the Settings window with appearance`.

### Task 0.4: String Catalog and project settings

**Files:**
- Create: `Picnest/Localizable.xcstrings`
- Modify: `project.yml` (add `vi` to known regions; keep `developmentLanguage: en`)
- Create: `PicnestTests/CatalogTests.swift`

**Interfaces:**
- Produces: `CatalogTests.catalog() -> [String: [String: StringUnit]]`, a JSON read of `Picnest/Localizable.xcstrings` through `#filePath` (3 folders up). Test `testEveryKeyHasTranslatedVietnamese` fails for each key whose `vi` is missing or has a `state` other than `translated`. Keys marked `shouldTranslate: false` are skipped.

- [ ] **Step 1: Write `testEveryKeyHasTranslatedVietnamese`** and `testNoStaleKeys` (no key has `extractionState` `stale`).
- [ ] **Step 2: Create an empty catalog** (`sourceLanguage: en`, `version: 1.0`, no strings). Add `vi` to `project.yml` known regions. Run `xcodegen generate`.
- [ ] **Step 3: Build.** Xcode adds the extracted keys to the catalog when `SWIFT_EMIT_LOC_STRINGS` is `YES`. If the build does not add keys, set `SWIFT_EMIT_LOC_STRINGS: YES` in `project.yml` base settings. Make sure the built app has `Contents/Resources/vi.lproj`.
- [ ] **Step 4: Run the catalog tests.** Expected: FAIL for every extracted key (no `vi` yet). This is the work list for task 0.5.
- [ ] **Step 5: Commit** `chore(i18n): add the string catalog and vi region`.

### Task 0.5: Move strings to the catalog and translate

**Files:**
- Modify: `Picnest/Sort/SortMessages.swift`, `Picnest/Review/SidebarView.swift`, and every file whose helper or ViewModel returns `String` to a view (`grep -rn "-> String" Picnest`).
- Modify: `Picnest/Localizable.xcstrings`

**Interfaces:**
- Produces: `SortMessages.text(for:)` and `SortMessages.saveFailed(_:)` return `String` built with `String(localized:)`. Views pass them to `Text(verbatim:)` or `Text(_: String)` only when the string comes from `String(localized:)`.
- Produces: row helpers (`SidebarView.row`) take `LocalizedStringKey` for the title.

- [ ] **Step 1: Write the failing test** `testSortMessageStoppedIsInCatalog` in `PicnestTests/SortMessagesTests.swift`: `SortMessages.text(for: SortError.stopped)` equals `"The sort stopped."`. Also `testCatalogHasKeyForEachSortError`: each `SortError` case has its key in the catalog.
- [ ] **Step 2: Run it.** Expected: FAIL (key not in catalog).
- [ ] **Step 3: Convert** each `SortMessages` literal to `String(localized: "…")`. Convert the helper parameters named in the Interfaces block. Fix every `Text(someString)` that holds a user-facing string.
- [ ] **Step 4: Plurals.** For each string with a count (for example `"\(n) photos"`), add plural variations in the catalog (`one`, `other`). Add test `testPhotoCountPlurals` in `SortMessagesTests` or the file that owns the string: 0, 1, 1000 read correctly in `en`.
- [ ] **Step 5: Translate every key to `vi`.** Set each `state` to `translated`. Keep `{n}`-style placeholders in the same order or use positional specifiers (`%1$lld`).
- [ ] **Step 6: Run the full app tests.** Expected: PASS, including the catalog tests.
- [ ] **Step 7: Commit** `feat(i18n): move UI strings to the catalog with vi`.

### Task 0.6: Language setting

**Files:**
- Create: `Picnest/Settings/LanguageStore.swift`
- Create: `PicnestTests/LanguageStoreTests.swift`
- Modify: `Picnest/Settings/SettingsView.swift`

**Interfaces:**
- Produces: `enum AppLanguage: String, CaseIterable, Identifiable { case system, en, vi }` with `var displayName: String` (**System**, **English**, **Tiếng Việt**; the last two never change by language).
- Produces: `@MainActor @Observable final class LanguageStore { init(defaults: UserDefaults); var language: AppLanguage { get set }; var needsRestart: Bool { get } }`. Setting `language` writes `AppleLanguages` (`[code]`) or removes it for `system`. `needsRestart` is `true` when `language` differs from the value at launch.

- [ ] **Step 1: Write the failing tests:** `testDefaultIsSystem`, `testSetViWritesAppleLanguages`, `testSetSystemRemovesKey`, `testUnknownCodeFallsBackToSystem` (write `["xx"]`), `testNeedsRestartOnlyAfterChange`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** `LanguageStore`.
- [ ] **Step 4: Add the Language picker** to `SettingsView`. When `needsRestart` is true, show the text "Restart Picnest to change the language." and a **Restart** button. Add both strings to the catalog with `vi`.
- [ ] **Step 5: Manual check B.** Choose **Tiếng Việt**, restart: every screen is Vietnamese. Choose **System**, restart: follows macOS.
- [ ] **Step 6: Commit** `feat(settings): add the language setting`.

### Task 0.7: Docs for contributors and terms

**Files:**
- Modify: `CONTRIBUTING.md`, `docs/dictionary.md`, `docs/specs/2026-10-21-macos-app-design.md` (delete the non-goal line "Interface languages other than English." in section 1.4), `docs/specs/2026-11-01-ui-redesign-design.md` (nothing to change unless a call changed).

- [ ] **Step 1: Add a "Translate Picnest" section** to `CONTRIBUTING.md`: open `Picnest/Localizable.xcstrings` in Xcode, add a language, fill every key, run `PicnestTests/CatalogTests`, and run the app with a pseudo-language scheme option (**Double-Length Pseudolanguage**).
- [ ] **Step 2: Add terms** to `docs/dictionary.md`: Appearance, Language setting, String Catalog, Chosen by you, Needs Review.
- [ ] **Step 3: Test the guide.** Follow the guide alone and add a language `fr` with 3 keys on a scratch branch. Make sure the catalog test reports the other keys. Delete the scratch branch.
- [ ] **Step 4: Commit** `docs: add the translation guide and new terms`.
- [ ] **Step 5: Merge phase 0** into `ui-redesign`. Tick the Status line.

---

## Phase 1: App shell

Read `Picnest/Review/ReviewView.swift`, `SidebarView.swift`, `SelectionBar.swift`, and `ReviewViewModel.swift` before you start.

### Task 1.1: Filter model

**Files:**
- Modify: `Picnest/Review/ReviewViewModel.swift`
- Test: `PicnestTests/ReviewViewModelTests.swift`

**Interfaces:**
- Produces: `enum PhotoFilter: CaseIterable { case all, needsReview, chosenByYou }`. `ReviewViewModel.filter: PhotoFilter { get set }` maps to `selectedItem` (`.all`, `.notSure`, `.changedByYou`). When `selectedItem` is a category, `filter` is `.all`.
- Produces: `ReviewViewModel.searchText: String { get set }`. The photo list shows only photos whose file name contains `searchText` (case and diacritic insensitive).
- Produces: `ReviewViewModel.thumbnailSize: Double { get set }` (range 80...240, default 160), saved in `UserDefaults` key `"thumbnailSize"`.

- [ ] **Step 1: Write failing tests:** `testFilterMapsToSidebarItem` (all 3 cases, both directions), `testSearchMatchesFileNameIgnoringCaseAndDiacritics` (`"anh"` finds `Ảnh_01.jpg`), `testSearchEmptyShowsAll`, `testThumbnailSizeIsClampedAndSaved` (`50` becomes `80`, `999` becomes `240`).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** the three properties. Search must work together with the current item and sort order. Invalidate the existing `cache` when `searchText` changes.
- [ ] **Step 4: Run the full app tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(review): add filter, search, and thumbnail size`.

### Task 1.2: Sidebar

**Files:**
- Modify: `Picnest/Review/SidebarView.swift`

**Interfaces:**
- Consumes: `ReviewViewModel.sidebarCounts`, `selectedItem`, `categories`.
- Produces: sections **Library** (All Photos, Needs Review), **Categories** (existing rows, drop and reorder kept), **Tools** (Duplicates), and a bottom group that holds the future items. Width 220 to 250 pt (`Theme.Metrics`). The old item **Changed by you** leaves the sidebar. It is now a chip (task 2.3).

- [ ] **Step 1: Restyle** to the mockups. Use `Theme` colors and the section titles of mockup 01. Keep drag of photos to a category and the category context menu.
- [ ] **Step 2: Rename strings.** "All photos" → "All Photos". "Not sure" → "Needs Review". Update the catalog `en` and `vi`. Update any test that reads these names.
- [ ] **Step 3: Run the full app tests.** Expected: PASS.
- [ ] **Step 4: Commit** `feat(ui): new sidebar`.

### Task 1.3: Inspector

**Files:**
- Create: `Picnest/Review/InspectorView.swift`
- Modify: `Picnest/Review/ReviewView.swift`

**Interfaces:**
- Produces: `struct InspectorView: View` with `init(model: ReviewViewModel)`. Shows for one selected photo: large preview, file name, category, date, dimensions, file size, confidence, and the **Move to…** button. Shows a short text when 0 photos are selected. Shows a count and the batch actions when more than 1 is selected.
- Reuse the existing suggestion, **Choose category…**, and **Accept** actions from `NotSureView`. Do not copy them. Extract shared parts into one view.

- [ ] **Step 1: Build** the view from mockups 01 and 02. Fields not in the app (Location, Tags, Notes) are left out (spec section 6).
- [ ] **Step 2: Manual check C.** Select 0, 1, and 3 photos. The panel shows the right state each time.
- [ ] **Step 3: Commit** `feat(ui): add the inspector`.

### Task 1.4: Window shell and toolbar

**Files:**
- Modify: `Picnest/Review/ReviewView.swift`

**Interfaces:**
- Consumes: `PhotoFilter`, `searchText`, `thumbnailSize` (task 1.1), `InspectorView` (task 1.3).
- Produces: toolbar with back and forward, title with photo count, search field (`.searchable`), thumbnail size slider, sort menu (existing `SortOrder`), and an inspector toggle bound to `@SceneStorage("inspectorShown")`. Use `.inspector(isPresented:)`.

- [ ] **Step 1: Replace the layout** in `ReviewView.swift` with the new shell. Keep every existing command and sheet working.
- [ ] **Step 2: Empty state.** When the folder has 0 photos, or the filter and search give 0 results, show one centered message with an action (**Clear search**, or **Choose Another Folder**).
- [ ] **Step 3: Manual check D.** Window at 1000 × 680 in `en` and `vi`. Nothing overlaps or is cut.
- [ ] **Step 4: Run the full app tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): new window shell and toolbar`. Merge phase 1. Tick the Status line.

---

## Phase 2: Screens

For each task: restyle on `Theme`, add new strings with `vi`, keep ViewModel rules, and compare with the mockup. Run the full app tests before each commit.

### Task 2.1: Welcome and Scan

**Files:** Modify `Picnest/Welcome/WelcomeView.swift`, `Picnest/Scan/ScanView.swift`.

- [ ] **Step 1: Welcome.** Choose Folder button, drop zone, recent folders as cards (short path, photo count, last opened, status), privacy line "Your photos stay on this Mac." Show **Continue** for an unfinished session. Show **Locate folder…** for a moved folder. Both exist in the ViewModel today. Read `WelcomeViewModel` first. Do not add data it does not have. If the card needs a photo count the ViewModel lacks, add a computed property with a test in `WelcomeViewModelTests`.
- [ ] **Step 2: Scan.** Folder name and path, found count, progress, **Cancel**, and the text that says Cancel does not delete cache or photos.
- [ ] **Step 3: Commit** `feat(ui): restyle welcome and scan`.

### Task 2.2: Photo tile and grid

**Files:** Modify `Picnest/Review/PhotoTile.swift`, `Picnest/Review/PhotoGridView.swift`.

- [ ] **Step 1: Tile.** Corner `Theme.Metrics.tileCorner`, selection ring with `Theme.selection`, file name under the tile, confidence badge only on uncertain photos, **Reviewed** or **Chosen by you** badge for photos the user decided. Columns follow `thumbnailSize`.
- [ ] **Step 2: Accessibility.** Each tile has a VoiceOver label: file name, category, and state. The selection state is not color only (a check mark shows too).
- [ ] **Step 3: Check E (Review Focus 5).** Put a white photo and a black photo in a test folder. In dark mode, selected tiles and badges stay readable. Record the result in the commit message.
- [ ] **Step 4: Commit** `feat(ui): restyle tiles and grid`.

### Task 2.3: Library view with chips and list mode

**Files:** Modify `Picnest/Review/ReviewView.swift`. Create `Picnest/Review/PhotoListView.swift`.

**Interfaces:**
- Consumes: `ReviewViewModel.filter` (task 1.1).
- Produces: a chip row **All**, **Needs review**, **Chosen by you** bound to `filter`. A grid/list switch bound to `@AppStorage("libraryLayout")` (`grid`, `list`). `PhotoListView(model:)` shows rows with a small thumbnail, name, category, date, size.

- [ ] **Step 1: Add the chip row** and the footer "N photos · Stored on this Mac" (plural catalog key).
- [ ] **Step 2: Add `PhotoListView`.** Selection and drag behave as in the grid. Reuse `SelectionBar`.
- [ ] **Step 3: Empty states** for each chip (Review Focus 3). Each has its own message.
- [ ] **Step 4: Commit** `feat(ui): add filter chips and list mode`.

### Task 2.4: Needs Review

**Files:** Modify `Picnest/Review/NotSureView.swift`, `Picnest/Review/SelectionBar.swift`, `Picnest/Review/InspectorView.swift`.

**Interfaces:**
- Produces in `ReviewViewModel`: `enum ReviewIssue: CaseIterable { case lowConfidence, noCategory, similarPhotos }` and `reviewIssue: ReviewIssue? { get set }`. The list in **Needs Review** shows only photos with that issue when it is set. Read how the model flags "not sure" and similar photos today. Do not change the rule. Map the issues to the existing data.

- [ ] **Step 1: Write failing tests** in `ReviewViewModelTests`: `testIssueFilterLowConfidence`, `testIssueFilterNoCategory`, `testIssueFilterSimilar`, `testNilIssueShowsAllNeedsReview`. Use the fixtures in `PicnestTests/Support.swift`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** `ReviewIssue` and the filter.
- [ ] **Step 3b: Search in Needs Review (open decision from task 1.1).** `notSureGroups`, `selectGroup`, `acceptGroup`, and `acceptAll` ignore `searchText`, while `visibleIDs` honors it. Make what the view shows and what **Accept** acts on the same set. Rule: show only matching photos, and make Accept N, Select Group, and Accept All Best Guesses act on matching photos only. Add tests for each.
- [ ] **Step 4: Restyle** the view: title with "N photos need a quick check", amber banner (closable), 3 filter menus, sort menu, floating selection bar (thumbnails of selected photos, "N selected", **Move to…**, **Ignore**, more menu). Use **Accept suggestion** in the inspector.
- [ ] **Step 5: Run tests.** Expected: PASS. Commit `feat(ui): restyle Needs Review`.

### Task 2.5: Category screen and Edit Category dialog

**Files:** Create `Picnest/Review/CategoryHeaderView.swift`, `Picnest/Review/EditCategorySheet.swift`. Modify `Picnest/Review/SidebarView.swift` (rename and icon actions use the sheet). Read `CategoryFolderService.swift` and `docs/plans/2026-10-30-category-folders-plan.md` first.

**Interfaces:**
- Produces: `CategoryHeaderView(category:photoCount:)` with icon, name, count, **Add Photos**, **Rename**, sort, more menu.
- Produces: `EditCategorySheet` with name field, icon picker, and folder row. The folder row is editable only if `CategoryFolderService` already supports a folder rename. Otherwise it is read only with **Reveal in Finder**. The sheet has the link **Create a collection instead**. Before phase 3, the link is hidden.
- Produces: `ReviewViewModel.validateCategoryName(_ name: String, excluding: CategoryID?) -> CategoryNameIssue?` with `enum CategoryNameIssue { case empty, duplicate, invalidFolderName }`. Use the same folder-name rules as `SortPlanner.folderNames(for:)`. Do not copy them. Call them.

- [ ] **Step 1: Write failing tests:** `testEmptyNameIsInvalid`, `testDuplicateNameIsInvalid`, `testNameWithSlashIsInvalidFolderName`, and `testVietnameseNameInNFCAndNFDIsTheSameFolder` (`"Ẩm thực"` composed and decomposed give the same folder name, and the second one counts as a duplicate).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement** `validateCategoryName`. If `SortPlanner` does not normalize to NFC, fix it there with a test in `PicnestCore/Tests/PicnestCoreTests/SortPlannerTests.swift`. This is a data fix, and the only core change in this phase.
- [ ] **Step 4: Build the header and sheet.** Show the issue text under the field.
- [ ] **Step 5: Run `swift test --package-path PicnestCore` and the app tests.** Expected: PASS. Commit `feat(ui): category header and edit sheet`.

### Task 2.6: Duplicates

**Files:** Modify `Picnest/Review/DuplicatesView.swift`.

- [ ] **Step 1: Restyle** with tabs **Exact copies** and **Similar photos**, groups side by side with size and file size, a clear **Keep** choice, **Not duplicates**, and a **Clean up** button that names the count to move to the Trash. Read `DuplicatesViewModel` first. Keep its rules.
- [ ] **Step 2: Commit** `feat(ui): restyle duplicates`.

### Task 2.7: Sort sheet

**Files:** Modify `Picnest/Sort/SortSheet.swift`.

- [ ] **Step 1: Restyle.** Keep Copy as the default and the extra confirm for Move. Keep the folder preview, progress, summary, **Show in Finder**, and **Undo Last Sort**.
- [ ] **Step 2: Commit** `feat(ui): restyle sort sheet`.

### Task 2.8: Final pass

**Files:** all of `Picnest/`; `docs/plans/2026-11-01-ui-redesign-plan.md`.

- [ ] **Step 1: Search for color literals.** `grep -rnE "Color\(red|Color\(\.sRGB|NSColor\(red|\.red\b|\.orange\b|\.green\b" Picnest` returns nothing outside `Theme.swift`. System semantic colors (`.primary`, `.secondary`) are fine.
- [ ] **Step 2: Run both test suites.** Expected: PASS, including `CatalogTests`.
- [ ] **Step 3: Manual checklist, in `en` and `vi`, in Light, Dark, and System:** Welcome, Scan, Library grid, Library list, Needs Review, Category, Edit Category, Duplicates, Sort sheet, Settings. At 1000 × 680, no text is cut.
- [ ] **Step 4: Accessibility.** Every icon-only button has a label. Keyboard focus shows on each control. With **Reduce Motion** on, no motion plays.
- [ ] **Step 5: Compare with the mockups.** Put each screen next to its PNG. Write the differences in a list. Ask the owner to accept them.
- [ ] **Step 5b: Make `CatalogTests` cover every language** in the catalog, not only `vi` (follow-up from task 0.7). Update the guide in `CONTRIBUTING.md` to match.
- [ ] **Step 6: Ask a native speaker** to review the Vietnamese text. Do not release before this.
- [ ] **Step 7: Merge phase 2** into `ui-redesign`. Tick the Status line. Ask the owner before any merge into `main`.

---

## Later phases

Write a detailed plan for each phase after phase 2 is merged. Reason: each phase depends on facts that the earlier phases and code reading give.

- **Phase 3 (Favorites, Collections, Recently Deleted).** First task: find how `MediaID` is made (`ScanService`, `MediaRepository`). Test that a favorite and a collection member survive a rescan, a Move sort, a category change that moves the file, and Trash then `TrashService.putBack`. New `Session` fields decode with `decodeIfPresent`, and an old `session.json` still opens (test in `SessionRepositoryTests`).
- **Phase 4 (Photo Editor).** Core Image. Edit value type with Reset and Undo. Output only through **Export edited copy**. The original file does not change (test: file hash before and after).
- **Phase 5 (Layout Editor).** Contact sheet first, then Collage. Export PNG and PDF. Test the output size for A4 landscape.
