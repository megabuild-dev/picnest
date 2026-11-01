---
id: picnest-ui-redesign-plan
title: Picnest UI Redesign Implementation Plan
type: plan
status: active
tags: [picnest, ui, theme, localization, swiftui, plan, collections, photo-editor, layout-editor]
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
- [x] Phase 2: Screens (tasks 2.1 to 2.8). Merged into `ui-redesign`. Owner steps open: manual checklist, mockup comparison, native-speaker review of the Vietnamese text.
- [x] Phase 3: Favorites, Collections, Recently Deleted (tasks 3.1 to 3.10). Merged into `ui-redesign`. Manual checks F, G, H and the sidebar comparison with mockups 01 to 03 wait for the owner.
- [x] Phase 4: Photo Editor (tasks 4.1 to 4.8). Merged into `ui-redesign`. Manual checks I, J, K wait for the owner.
- [ ] Phase 5: Layout Editor (tasks 5.1 to 5.11). Planned, not started.

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

## Phase 3: Favorites, Collections, Recently Deleted

Sub-branch: `feature/ui-redesign/phase-3-collections`. Spec: section 4.4, the sidebar of section 4.2, section 6, mockups 01, 02, 03.
Core tests use Swift Testing (`@Test func name()`), as in `PicnestCore/Tests/PicnestCoreTests`. Read `ReviewService.swift`, `Session.swift`, `ScanService.swift`, and `TrashService.swift` before you start.

### Key decision: the photo key

`MediaID` is the path of the file relative to the source folder, in NFC (`Domain/Media.swift`). `MediaRepository` makes it at each scan. Favorites and collection members use `MediaID`. The table gives the result of each event.

| Event | What the code does | Favorite and member |
|-------|--------------------|---------------------|
| Rescan, file at the same path | Same path gives the same `MediaID` | Kept (task 3.4) |
| Rescan, file renamed or moved in Finder | New path gives a new `MediaID`. States are lost too | **Lost** |
| Category change (`move(_:to:)`, drag) | Changes `states` only. No file moves | Kept |
| **Done** (`organizeInPlace` → `applyOrganize`) | Moves files, then `ReviewService.rekey` | Kept, if `rekey` maps them (task 3.3) |
| Category rename that renames its folder | `renameFolder` → `pathChanges` → `rekey` | Kept, if `rekey` maps them (task 3.3) |
| Move sort (`SortService.run`, mode `.move`) | Files go outside the source. The session is not re-keyed | Kept in the session. **Undo Last Sort** brings the files back to the same paths |
| Rescan after a Move sort, with no undo | The files are not in the source folder | **Lost**, as for category picks. No key can fix this |
| Trash, then **Put Back** (undo or Recently Deleted) | The record keeps the `MediaID`. The file returns to the same path | Kept, if trash does not strip them (task 3.3) |
| Trash, then rescan before **Put Back** | The file is not in the new scan. Rescan clears `trashed` | **Lost**. A later Put Back in Finder gives a new photo with no favorite |
| Source folder moved (`SessionRepository.relink`) | Only `sourcePath` changes | Kept |
| **Start Over** (`deleteSessionFile`) | Deletes `session.json` | **Lost**. The confirmation text says so (task 3.6) |

The plan rejects content hash as the key, for 3 reasons:
- `HashRepository` hashes only files whose size matches another file. A key for every photo needs a full read of the library at each scan.
- 2 exact copies have 1 hash. A favorite on 1 copy then marks both copies, and Duplicates clean-up gets confusing.
- The only event that a hash saves is a rename in Finder. The app already treats that file as a new photo.

### Key decision: where the data lives

`Session` gets 2 fields: `favoriteIDs` and `collections` (spec 4.4). `SessionRepository` saves them. There is no new repository file. Reason: `ReviewService` saves the whole session after each change and each background recalculation. A second writer of `session.json` races with it and loses writes. A second file needs a second re-key at **Done** and at rescan, with no atomic write.
A new service, `CollectionService`, owns the rules as pure functions (as `SortPlanner` does). `ReviewService` applies each rule to its session and saves. Views and ViewModels never write the session.
Favorite and collection changes are not undo steps. `ReviewChange` stays as it is. **Delete Collection** asks for confirmation for this reason.

### Phase 3 Review Focus

Each line has a test or a check in the named task.

1. 2 exact copies of 1 photo. A favorite on 1 copy does not mark the other copy. Task 3.2.
2. A favorite photo goes to the Trash. It leaves Favorites and its counts. **Put Back** makes it a favorite again. Tasks 3.3 and 3.6.
3. **Put Back** when the Trash is empty or a file exists at the original path. An alert shows the reason, and the photo stays in Recently Deleted. Task 3.5.
4. A collection name in NFC and in NFD, or with spaces around it, is a duplicate of the same name. Task 3.2.
5. The user types `.` in the search field or a name field. No favorite changes. Task 3.8 (check G).

### Task 3.1: Domain types and session fields

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Domain/Collection.swift`
- Modify: `PicnestCore/Sources/PicnestCore/Domain/Session.swift`
- Test: `PicnestCore/Tests/PicnestCoreTests/SessionRepositoryTests.swift`

**Interfaces:**
- Produces: `public typealias CollectionID = UUID`.
- Produces: `public struct PhotoCollection: Codable, Sendable, Hashable, Identifiable { var id: CollectionID; var name: String; var memberIDs: [MediaID]; var order: Int }` with `init(id: CollectionID = UUID(), name: String, memberIDs: [MediaID] = [], order: Int)`. The name `Collection` clashes with the Swift protocol, so do not use it.
- Produces: `public enum CollectionNameIssue: Sendable, Hashable { case empty, duplicate }`.
- Produces: `Session.favoriteIDs: Set<MediaID>` and `Session.collections: [PhotoCollection]`. Both are new `init` parameters with default `[]`.

- [ ] **Step 1: Write the failing tests:** `oldSessionWithoutFavoritesAndCollectionsDecodes` (copy the JSON method of `oldSessionWithoutNotDuplicateKeysDecodes`; both fields are empty), `favoriteIDsAreSavedSorted` (`["b.jpg", "a.jpg"]` encodes as `["a.jpg","b.jpg"]`). Add both fields with values to `sessionWithEveryFieldRoundTrips`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter SessionRepositoryTests`. Expected: build fails (`favoriteIDs` not defined).
- [ ] **Step 3: Implement.** Add the 2 keys to `CodingKeys`, `init(from:)` (`decodeIfPresent … ?? []`), and `encode(to:)` (`favoriteIDs.sorted()`). Add the doc lines in the style of `trashed`.
- [ ] **Step 4: Run the core tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): add favorite and collection fields to the session`.

### Task 3.2: Collection rules

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/CollectionService.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/CollectionServiceTests.swift`

**Interfaces:**
- Consumes: task 3.1 types.
- Produces: `public enum CollectionService` with static, pure functions. Each `-> Bool` function returns `true` when the session changed. A "usable id" is in `scan.media` and not in `trashedIDs`. The functions ignore other ids.
  - `validateName(_ name: String, excluding: CollectionID?, among: [PhotoCollection]) -> CollectionNameIssue?`. Trim spaces. Compare `precomposedStringWithCanonicalMapping`, case-insensitive. A category can have the same name.
  - `toggleFavorite(_ ids: [MediaID], in s: inout Session) -> Bool`. If every usable id is a favorite, remove all. Else add all (rule of Apple Photos).
  - `create(name: String, adding ids: [MediaID], in s: inout Session) -> CollectionID?`. Nil when the name has an issue. Stores the trimmed name. `order` is the highest order + 1.
  - `rename(_ c: CollectionID, to name: String, in s: inout Session) -> Bool`, `delete(_ c: CollectionID, in s: inout Session) -> Bool` (renumbers `order` from 0).
  - `add(_ ids: [MediaID], to c: CollectionID, in s: inout Session) -> Bool` (appends in the given order, no repeats), `remove(_ ids: [MediaID], from c: CollectionID, in s: inout Session) -> Bool`.
  - `rekey(_ map: [MediaID: String], in s: inout Session)` and `prune(keeping ids: Set<MediaID>, in s: inout Session)`.
  - `visibleFavorites(in s: Session) -> Set<MediaID>` and `visibleMembers(of c: CollectionID, in s: Session) -> [MediaID]`. Both leave out trashed ids.

- [ ] **Step 1: Write the failing tests:** `nameIsTrimmedAndEmptyIsInvalid` (`"  "` gives `.empty`), `nameInNFDIsDuplicateOfNFC` (`"Ẩm thực"` composed and decomposed; Review Focus 4), `nameDifferingOnlyInCaseIsDuplicate`, `renameToOwnNameIsValid` (`excluding:`), `toggleFavoriteOnMixedSelectionAddsAll`, `toggleFavoriteWhenAllAreFavoritesRemovesAll`, `favoriteOfOneExactCopyDoesNotMarkTheOther` (`a.jpg` and `copy/a.jpg`, same size; Review Focus 1), `unknownAndTrashedIDsAreIgnored`, `addKeepsOrderWithoutRepeats`, `deleteRenumbersOrder`, `rekeyMovesFavoritesAndMembers`, `pruneDropsMissingIDs`, `visibleFavoritesLeaveOutTrashed`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter CollectionServiceTests`. Expected: build fails.
- [ ] **Step 3: Implement** `CollectionService`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): add the collection rules`.

### Task 3.3: Review service owns favorites and collections

**Files:**
- Modify: `PicnestCore/Sources/PicnestCore/Services/ReviewService.swift`
- Test: `PicnestCore/Tests/PicnestCoreTests/ReviewServiceTests.swift`, `SessionRepositoryTests.swift`

**Interfaces:**
- Consumes: `CollectionService` (task 3.2).
- Produces on `ReviewService`: `toggleFavorite(_ ids: [MediaID])`, `createCollection(name: String, adding ids: [MediaID]) -> CollectionID?`, `renameCollection(_ c: CollectionID, to name: String) -> Bool`, `deleteCollection(_ c: CollectionID)`, `addToCollection(_ ids: [MediaID], _ c: CollectionID)`, `removeFromCollection(_ ids: [MediaID], _ c: CollectionID)`. Each calls the rule and then `save()` when the rule returns `true`.
- Rule: do not route these through `perform`. Its guard compares only `categories` and `states`, so the change is lost. They push no undo step and do not clear redo.
- Rule: `rekey(_:)` calls `CollectionService.rekey`. `trashFiles` and `strip` do not touch favorites or members.

- [ ] **Step 1: Write the failing tests:** `favoriteChangeIsSavedAndIsNotAnUndoStep` (reload from `sessions`; `canUndo` stays `false`), `applyOrganizeReKeysFavoritesAndMembers` (extend the setup of `applyOrganizeReKeysTheSession`), `folderRenameReKeysFavoritesAndMembers` (extend `renamingACategoryRenamesItsFolderAndRekeysThePhotos`), `trashedFavoriteStaysInTheSessionAndUndoBringsItBack` (`moveToTrash`, then `visibleFavorites` lacks it, `undo()`, `settled()`, it is back; Review Focus 2), `undoOfAMoveKeepsFavorites` (a favorite and `move`, then `undo`). In `SessionRepositoryTests`: `relinkKeepsFavoritesAndCollections`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the methods and the `rekey` change.
- [ ] **Step 4: Run the core tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): review service keeps favorites and collections`.

### Task 3.4: Rescan and Move sort keep the data

**Files:**
- Modify: `PicnestCore/Sources/PicnestCore/Services/ScanService.swift` (`runRescan`)
- Test: `PicnestCore/Tests/PicnestCoreTests/ScanServiceTests.swift`, `LibraryServiceTests.swift`

**Interfaces:**
- Consumes: `CollectionService.prune(keeping:in:)`.
- Rule: prune to the ids of the new scan, `Set(scan.media.map(\.id))`. Do not subtract `old.trashedIDs`. So a photo put back with Finder keeps its favorite.
- Rule: rescan still sets `session.trashed = []`. Recently Deleted is empty after a rescan. The files stay in the macOS Trash. This is a loss and an owner question (see "Open questions").

- [ ] **Step 1: Write the failing tests** with the `rescan(_:_:source:)` helper: `rescanKeepsFavoritesAndMembersAtTheSamePath`, `rescanDropsFavoritesAndMembersOfRemovedFiles`, `rescanKeepsFavoriteOfAFileThatIsBackAtItsPath` (old session lists it in `trashed`). In `LibraryServiceTests`, `moveSortThenUndoKeepsFavorites`: Move sort with a real journal (copy the setup of `undoLastSortReversesTheJournalAndClearsSortedAt`), `undoLastSort`, rescan, the favorite is there.
- [ ] **Step 2: Run** them. Expected: only `rescanDropsFavoritesAndMembersOfRemovedFiles` fails (`var session = old` keeps every id). The others pass already. Keep them as guards.
- [ ] **Step 3: Implement** the prune in `runRescan`. Update its doc comment.
- [ ] **Step 4: Run the core tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): rescan keeps favorites and collections of found files`.

### Task 3.5: Put Back from Recently Deleted

**Files:**
- Modify: `PicnestCore/Sources/PicnestCore/Domain/Session.swift` (`TrashedPhoto`), `Services/ReviewService.swift`, `Services/ThumbnailService.swift`
- Test: `ReviewServiceTests.swift`, `SessionRepositoryTests.swift`, `ThumbnailServiceTests.swift`

**Interfaces:**
- Produces: `TrashedPhoto.stateBeforeTrash: PhotoState?` (new `init` parameter, default `nil`). Synthesized `Codable` decodes a missing key as `nil`. `trashFiles` fills it from `session.states` before `strip`.
- Produces: `ReviewService.putBack(_ ids: [MediaID])` and `public private(set) var lastPutBackErrors: [TrashError]`. It runs through `runFileTask`, so it waits for a running ⌘Z and blocks Sort and Rescan (`isMovingFiles`). Wait with `settled()`.
- Rule: extract 1 private helper `putBackFiles(_ records: [TrashedPhoto]) async -> (back: Set<MediaID>, errors: [TrashError])`. The undo put-back and `putBack(_:)` both call it. Do not copy the loop.
- Rule: a photo that comes back gets `stateBeforeTrash` when `refersOnly(to:)` the current categories. Else it gets no state, and the classifier sorts it again. Example places do not come back. The step is not an undo step and clears the redo stack (`redoEpoch += 1`). An old undo step for the same photo then does nothing for it.
- Produces: `ThumbnailService.thumbnail(at url: URL, maxPixel: Int) async -> CGImage?`. `thumbnail(for:source:maxPixel:)` calls it.

- [ ] **Step 1: Write the failing tests:** `oldTrashedPhotoWithoutStateDecodes`, `trashRecordsTheStateBeforeTrash`, `putBackRestoresFileStateAndFavorite` (manual pick and favorite are back; the record is gone), `putBackOfAnEmptiedTrashKeepsTheRecord` (`FakeTrashFileOps.forget`; `lastPutBackErrors` holds 1 `cannotPutBack`; Review Focus 3), `putBackWhenTheOriginalPathIsTakenKeepsTheRecord`, `putBackClearsRedo`, `putBackDropsAStateOfADeletedCategory`, `thumbnailAtURLReadsAnyFile`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the field, the helper, `putBack(_:)`, and the thumbnail method.
- [ ] **Step 4: Run the core tests.** Expected: PASS, with the old Trash undo tests unchanged.
- [ ] **Step 5: Commit** `feat(core): put back photos from Recently Deleted`.

### Task 3.6: ViewModel items, counts, and actions

**Files:**
- Modify: `Picnest/Review/ReviewViewModel.swift`
- Create: `PicnestTests/CollectionsViewModelTests.swift` (use the fixtures of `ReviewViewModelTests`; move a shared helper to `PicnestTests/Support.swift` instead of a copy)
- Modify: `Picnest/Localizable.xcstrings`

**Interfaces:**
- Consumes: tasks 3.2, 3.3, 3.5.
- Produces: `SidebarItem` cases `.favorites`, `.collection(CollectionID)`, `.recentlyDeleted`. Update every switch on it: `includes` (new parameter `members: Set<MediaID>?`), `title`, `sidebarCounts`, `bodyKind`, `showsFilterChips` (`false`), `emptyState`, `showsThumbnailSlider`, `filter`.
- Produces: `BodyKind.recentlyDeleted`. `visibleIDs` for `.recentlyDeleted` reads `session.trashed`, newest `time` first, then id. Search applies. The other new items use `visibleMedia` and `sortOrder`.
- Produces: `EmptyState` cases `.noFavorites`, `.emptyCollection`, `.nothingDeleted`.
- Produces: `collections: [PhotoCollection]` (by `order`), `isFavorite(_ id: MediaID) -> Bool`, `toggleFavoriteSelection()`, `addSelection(to c: CollectionID)`, `removeSelectionFromCollection()` (only when `selectedItem` is a collection), `dropOnCollection(_ ids: [MediaID], _ c: CollectionID) -> Bool`, `putBackSelection()`, `putBackErrorMessage: String?` (text from `CoreErrorMessages.text(for:)`).
- Produces: `enum CollectionEditor: Identifiable { case new(name: String, adding: [MediaID]); case rename(CollectionID) }`, `editingCollection: CollectionEditor?`, `requestNewCollection(name: String = "", adding: [MediaID])`, `saveCollection(name: String) -> Bool`, `validateCollectionName(_ name: String, excluding: CollectionID?) -> CollectionNameIssue?`, `deletingCollection: CollectionID?`, `deleteCollection(_ c: CollectionID)`.
- Rule: when the user deletes the selected collection, set `selectedItem` to `.all`.
- Copy (en): **Favorites**, **Collections**, **Recently Deleted**, **No Favorites** / "Click the heart on a photo to add it here.", **This Collection Is Empty** / "Drag photos here, or click Add Photos.", **Nothing Recently Deleted** / "Photos you move to the Trash show here until the next rescan.", "A collection with this name already exists.". Reuse the key "Enter a name." Start Over text gets the sentence "Your favorites and collections are lost too." in both variants. vi draft: **Mục ưa thích**, **Bộ sưu tập**, **Đã xóa gần đây** (use the `xóa` spelling of the catalog).

- [ ] **Step 1: Write the failing tests:** `testFavoritesListsOnlyVisibleFavorites` (a trashed favorite is not listed; Review Focus 2), `testCollectionListsItsMembers`, `testSidebarCountsForNewItems` (favorites, each collection, recently deleted), `testRecentlyDeletedListsNewestFirst`, `testRecentlyDeletedHonorsSearch`, `testToggleFavoriteSelection`, `testNewCollectionAddsTheSelection`, `testDeletingTheSelectedCollectionSelectsAllPhotos`, `testRemoveFromCollectionOnlyInACollection`, `testEmptyStatesOfNewItems`, `testStartOverMessageNamesFavoritesAndCollections`, `testNewItemsHideChipsAndShowSlider`.
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/CollectionsViewModelTests`. Expected: build fails.
- [ ] **Step 3: Implement.** Add every new string with `en` and `vi` in this commit.
- [ ] **Step 4: Run the full app tests** and `python3 -I scripts/sync-string-catalog.py --check`. Expected: PASS, exit 0.
- [ ] **Step 5: Commit** `feat(review): favorites, collections, and recently deleted in the view model`.

### Task 3.7: Sidebar sections and the collection sheet

**Files:**
- Modify: `Picnest/Review/SidebarView.swift`, `Picnest/Review/ReviewView.swift` (host the sheet and the delete dialog, as for categories), `Picnest/Localizable.xcstrings`
- Create: `Picnest/Review/CollectionNameSheet.swift`

**Interfaces:**
- Consumes: task 3.6.
- Produces: **Library** gets **Favorites** (`heart`) after **Needs Review**. A **Collections** section between Library and Categories, with a `+` button in its header (label "New Collection"). Each row: `square.stack` icon, name with `Text(verbatim:)`, count, drop target of `MediaIDs`, context menu **Rename…**, **Delete…**. **Recently Deleted** (`trash`) is the last section, with no title, above the preferences bar.
- Produces: `CollectionNameSheet(model:editor:)` with a name field, the issue text under it, **Cancel**, and **Create** or **Save**. Delete dialog: title `Delete the collection “%@”?`, text "The photos stay in their folders.", button **Delete Collection**.

- [ ] **Step 1: Build** the sections. Reuse the existing `row` helper and the drop highlight of `categoryRow`. Extract the highlight into 1 modifier for both rows.
- [ ] **Step 2: Build** the sheet and the dialog. Add the strings with `vi`.
- [ ] **Step 3: Manual check F.** In `en` and `vi`, at 1000 × 680: create, rename, drop 3 photos on, and delete a collection with a 40-letter name. Nothing is cut except by an ellipsis.
- [ ] **Step 4: Run the full app tests.** Expected: PASS. Commit `feat(ui): sidebar favorites, collections, and recently deleted`.

### Task 3.8: Favorite and collection actions, Recently Deleted screen

**Files:**
- Modify: `Picnest/Review/PhotoTile.swift`, `InspectorView.swift`, `SelectionBar.swift` (`PhotoContextMenu`, selection actions), `PhotoGridView.swift`, `PhotoListView.swift`, `ReviewView.swift`, `ReviewViewModel.swift` (thumbnail of a trashed id), `Picnest/Localizable.xcstrings`

**Interfaces:**
- Consumes: task 3.6, `ThumbnailService.thumbnail(at:maxPixel:)` (task 3.5).
- Produces: a heart button on the tile, bottom right. It shows on hover, and always for a favorite (`heart.fill`, `Theme.accent`). A click toggles only that photo and does not change the selection. The list row shows the same button. The VoiceOver label adds "Favorite", and an accessibility action toggles it.
- Produces: inspector heart button next to the file name (mockup 01). Labels **Add to Favorites** and **Remove from Favorites**.
- Produces: context menu items **Add to Favorites** or **Remove from Favorites**, **Add to Collection** (menu of collections, then **New Collection…**), and **Remove from Collection** in a collection. The selection bar more menu gets the same items. Reuse 1 view for both.
- Produces: in Recently Deleted, the context menu has only **Put Back**. The selection bar shows **Put Back**. The inspector shows the facts and **Put Back**. `ReviewViewModel.thumbnail(_:maxPixel:)` reads `trashPath` for a trashed id.
- Produces: key `.` toggles the favorite of the selection. Use `.onKeyPress(characters:)` on the focused grid and list only, not a menu shortcut. A menu shortcut takes the key from text fields.

- [ ] **Step 1: Build** the heart, the inspector button, and the menus.
- [ ] **Step 2: Build** the Recently Deleted body and the put-back error alert.
- [ ] **Step 3: Manual check G (Review Focus 5).** Type `.` in the search field and in the collection name sheet. No favorite changes. Press `.` with the grid focused. The favorite changes.
- [ ] **Step 4: Manual check H.** Trash 2 photos. Recently Deleted shows their thumbnails from `~/.Trash` in the sandboxed app. If the sandbox blocks the read, the photo glyph shows. Write the result in the commit message. **Put Back** returns each photo to its category.
- [ ] **Step 5: Run the full app tests.** Expected: PASS. Commit `feat(ui): favorite and collection actions and the recently deleted screen`.

### Task 3.9: Add Photos and Create a collection instead

**Files:**
- Create: `Picnest/Review/AddPhotosSheet.swift`
- Modify: `Picnest/Review/CategoryHeaderView.swift` (extract the shared header layout), `Picnest/Review/EditCategorySheet.swift`, `Picnest/Review/ReviewViewModel.swift`, `ReviewView.swift`, `Picnest/Localizable.xcstrings`
- Test: `PicnestTests/CollectionsViewModelTests.swift`

**Interfaces:**
- Produces: `enum AddPhotosTarget: Identifiable, Hashable { case category(CategoryID), collection(CollectionID) }`, `ReviewViewModel.addingPhotos: AddPhotosTarget?`, `addPhotosCandidates(for: AddPhotosTarget) -> [MediaID]` (visible photos not already in the target), `addPhotos(_ ids: [MediaID], to: AddPhotosTarget)`. A category target calls `review.move` (manual picks; no file moves before **Done**). A collection target calls `addToCollection`.
- Produces: `AddPhotosSheet(model:target:)`: a search field, a grid of `ThumbnailImage` with multi-select, and **Add N Photos** (plural key). Reuse `ThumbnailImage`.
- Produces: 1 header view for a category and a collection: icon, name, count, **Add Photos**, **Rename**, sort, more menu (mockup 03). Do not copy `CategoryHeaderView`. Make it take the icon and the actions.
- Produces: in `EditCategorySheet`, the row **Create a collection instead** with "Group photos without moving files." (mockup 03). It closes the sheet and calls `requestNewCollection(name: category.displayName, adding: [])`. The category does not change.

- [ ] **Step 1: Write the failing tests:** `testAddPhotosCandidatesLeaveOutMembers`, `testAddPhotosToCategoryMakesManualPicks`, `testAddPhotosToCollectionAppendsMembers`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the ViewModel part, then the sheet, the header, and the row. Add strings with `vi`.
- [ ] **Step 4: Run the full app tests.** Expected: PASS. Commit `feat(ui): add photos and create a collection instead`.

### Task 3.10: Docs and final pass

**Files:** `docs/dictionary.md`, `docs/specs/2026-11-01-ui-redesign-design.md`, this plan.

- [ ] **Step 1: Dictionary.** Add Favorite, Collection, Recently Deleted, Put Back. Each says if it moves a file. Example: "Collection: a named group of photos. It does not move a file."
- [ ] **Step 2: Spec 4.4.** Add 2 lines: the key is `MediaID`, and the data is in `Session`. Link to this plan section. Name the 4 loss events: Finder rename, rescan after a Move sort, rescan while a photo is in the Trash, **Start Over**.
- [ ] **Step 3: Run both test suites and the catalog check.** Expected: PASS, exit 0.
- [ ] **Step 4: Compare** the sidebar with mockups 01, 02, 03 in Light and Dark. Write the differences in a list for the owner.
- [ ] **Step 5: Merge phase 3** into `ui-redesign`. Tick the Status line.

### Open questions for the owner

Each has a default in the tasks above. Change a default before its task starts.

1. Rescan empties Recently Deleted (task 3.4). Default: keep this rule. The files stay in the macOS Trash.
2. **Start Over** deletes favorites and collections (task 3.6). Default: yes, with a warning. Other choice: a separate file that **Start Over** keeps.
3. **Create a collection instead** fills in only the name (task 3.9). Default: the category and its photos stay. Other choice: also add the photos of the category.
4. Favorite and collection changes are not undo steps (task 3.3). Default: no undo, and a confirmation before **Delete Collection**.

---

## Phase 4: Photo Editor

Sub-branch: `feature/ui-redesign/phase-4-photo-editor`. Spec: section 4.5, sections 3, 6 (row "Edit tabs"), 7 (calls 5 and 7). Mockup: `design/picnest-ui-04-photo-editor.png`. Design text: section 8.
Core tests use Swift Testing (`@Test func name()`). App tests use XCTest (`func testName()`). Read `ImageRepository.swift`, `ThumbnailService.swift`, `SortPlanner.swift` (`uniqueName`), `ReviewCommands.swift`, `ReviewView.swift`, `InspectorView.swift`, and `PicnestCore/Tests/PicnestCoreTests/Support/TestImages.swift` before you start.

### Facts from the code

- The app has no App Sandbox (`project.yml`: `ENABLE_APP_SANDBOX: NO`). The export needs no new entitlement. The save panel is for user choice, not for sandbox access.
- No code uses Core Image today. `ImageRepository` decodes with ImageIO and `kCGImageSourceCreateThumbnailWithTransform`, so its images are upright (EXIF orientation applied).
- ImageIO on macOS 15 writes `public.jpeg`, `public.heic`, `public.png`, `public.tiff`, and `com.compuserve.gif`. It cannot write WebP (`CGImageDestinationCopyTypeIdentifiers`, checked 2026-11-01).
- The data has no "Edited" notion. Spec call 5 renamed "Edited by me" to **Chosen by you** to keep the word "Edited" for this editor. This phase saves no recipe, so it adds no badge, no flag, and no `Session` field.
- The "preview" of the spec is the system Quick Look panel (`QuickLookPreview.swift`). An app cannot add a button to it. Double-click and Space open Quick Look (`PhotoGridView.swift`), and they keep this rule.
- There is 1 window (`Window("Picnest", id: "main")`). `ReviewViewModel.swift` has 1,609 lines. The editor gets its own ViewModel.
- ⌘Z goes to the review through `ReviewCommands` and `UndoRouting`. With the editor open, ⌘Z must not undo a category move.

### Key decisions

**Scope.** The table lists what this phase does and does not do.

| In this phase | Out of this phase |
|---------------|-------------------|
| Crop with aspect ratios, straighten | A saved recipe, an "Edited" badge |
| Rotate 90° left and right, flip horizontal and vertical | Auto-enhance, filters, other adjustments |
| Exposure, Contrast, Warmth, Saturation | RAW, HDR, and 16-bit output |
| Reset, Undo, Redo, **Show Original** | Video, batch edit, a photo in Recently Deleted |
| Filmstrip of the set, **Export edited copy** | Export to the Photos app, a Share button |

**Entry points (a change from spec 4.5 "opens from the preview").** The inspector gets an **Edit** button for 1 photo. The photo context menu gets **Edit Photo…**. The menu item **Image > Edit Photo** has ⌘E. Double-click stays Quick Look. Task 4.8 writes this change into spec 4.5.

**Where it opens.** The editor replaces the detail column of `ReviewView`. While it is open, the sidebar collapses (`NavigationSplitViewVisibility.detailOnly`), the inspector hides, and the toolbar shows only the editor items. On close, the sidebar, the inspector state, the selection, and the scroll position come back. There is no tab bar (spec 6 and call 7).

**The edit value.** `PhotoEdit` in `PicnestCore/Domain` holds the full edit. The pipeline order is fixed: EXIF orientation, quarter turns, flip, straighten, crop, adjustments, all in the frame the user sees. `PhotoEdit.flip` negates `straighten`, so a flip keeps the same picture, mirrored.
- Straighten turns the image about its center and scales it up so that no empty corner shows (`CropGeometry.straightenScale`).
- The crop is a rect in 0…1 units of the frame after straighten, quarter turns, and flip. Origin is top left. So 1 value works on the preview and on the full-size image.
- A quarter turn or a flip moves the crop rect with the image.

**Adjustment map.** Each slider has the range -100…100, step 1, default 0. `PhotoEditService.filterValues(for:)` is the 1 place that maps a slider value to a filter value:

| Slider | Core Image filter | Value at -100 / 0 / +100 |
|--------|-------------------|--------------------------|
| Exposure | `CIExposureAdjust` `inputEV` | -2 / 0 / +2 |
| Contrast | `CIColorControls` `inputContrast` | 0.75 / 1 / 1.25 |
| Saturation | `CIColorControls` `inputSaturation` | 0 / 1 / 2 |
| Warmth | `CITemperatureAndTint` | Neutral 6500 K. Target from 4500 K to 8500 K. The test fixes the direction: +100 makes red higher than blue on gray |

**Undo.** `EditHistory` is a value type in Core. A button press is 1 step. A slider drag or a crop drag is 1 step, committed when the drag ends. **Reset** is 1 step, so ⌘Z brings the edit back. The history keeps 100 steps. A step to another photo clears it.

**Preview and performance.** The preview reads `ThumbnailService.thumbnail(at:maxPixel: 1600)`, so it shares the app cache. Each change starts a new preview task and cancels the old one. The filter work runs off the main actor on 1 shared `CIContext`. Only the export decodes the full-size image.

**Export.** The format list is JPEG, HEIC, and PNG. The default follows the original: `jpg`/`jpeg` → JPEG, `heic`/`heif` → HEIC, `png`/`tiff`/`gif` → PNG, `webp` → JPEG. JPEG and HEIC quality is 0.9. A GIF exports its first frame. An image with alpha that goes to JPEG or HEIC gets a white background.
- The save panel suggests `<stem> edited.<ext>` in the folder of the original. If that name exists, the name gets ` 2`, ` 3`, and so on (`SortPlanner.uniqueName`, made internal).
- The copy keeps the EXIF, TIFF, GPS, and IPTC data of the original. It gets orientation 1, the new pixel size, and no embedded thumbnail.
- Core refuses a destination that is the original or any photo of the session, even after the user clicks **Replace** in the panel. `ProtectedFiles` makes the compare: canonical source folder, NFC, case-insensitive (APFS default).
- The writer writes a temp file in the destination folder, then moves it into place. A failed export leaves no file.
- If the copy goes into the source folder, the next rescan adds it as a new photo. The editor does not add it to the session.

**Files that move while the editor is open.** `canEdit` needs `canSortOrRescan`. While the editor is open, `canSortOrRescan` is `false`. So **Done**, **Sort Photos…**, **Rescan**, **Undo Last Sort**, and **Start Over…** (⇧⌘R) are off. Before an export, the service checks that the original still exists.

**Leaving with changes.** **Back**, Esc, a filmstrip step, ← and → ask "Discard your edits?" when the edit is not `.original`. Buttons: **Discard Edits** and **Cancel**. An export does not clear the edit, because the user can export again.

### Phase 4 Review Focus

Each line has a test or a check in the named task.

1. A JPEG with EXIF orientation 6 (rotated 90° on the camera). The preview and the export are upright, and the export has orientation 1 and swapped pixel size. Tasks 4.3 and 4.4.
2. The user picks the file name of the original in the save panel and clicks **Replace**. The export fails with a message, and the original keeps its SHA-256, size, and modification date. Task 4.4.
3. The editor is open and the user presses ⌘Z or ⇧⌘R. ⌘Z undoes the last edit, not a category move. **Start Over…** is off. Task 4.6.
4. A quarter turn left and a quarter turn right give the same pixel size but different images. A flip does not change the size. Corner colors of a 4-color PNG prove each one. Task 4.3.
5. The disk is full or the folder is read-only during an export. The message shows, no temp file stays, and the original does not change. Task 4.4.

### Task 4.1: Edit types and history

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Domain/PhotoEdit.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/PhotoEditTests.swift`

**Interfaces:**
- Produces: `public enum AdjustmentKind: String, CaseIterable, Sendable { case exposure, contrast, warmth, saturation }`.
- Produces: `public struct NormalizedRect: Sendable, Hashable { var x, y, width, height: Double; static let full }`.
- Produces: `public enum AspectRatio: String, CaseIterable, Sendable, Hashable { case original, freeform, square, fourThree, threeTwo, sixteenNine }` with `func ratio(frame: PixelSize, original: PixelSize) -> Double?` (`nil` for `freeform`). Fixed ratios follow the frame: a portrait frame gives 3:4, not 4:3.
- Produces: `public struct PhotoEdit: Sendable, Hashable` with `straighten: Double` (degrees, clamped to -45…45), `quarterTurns: Int` (clockwise, 0…3), `flipHorizontal: Bool`, `flipVertical: Bool`, `crop: NormalizedRect`, `aspect: AspectRatio`, `subscript(_ kind: AdjustmentKind) -> Int` (clamped to -100…100), `static let original`, `var isOriginal: Bool`, `mutating func rotate(clockwise: Bool)`, `mutating func flip(horizontal: Bool)`.
- Produces: `public enum ExportFormat: String, CaseIterable, Sendable { case jpeg, heic, png }` with `var utType: UTType`, `var fileExtension: String`, `static func defaultFormat(forExtension ext: String) -> ExportFormat` (rules in "Export").
- Produces: `public struct EditHistory: Sendable { init(limit: Int = 100); var current: PhotoEdit { get }; mutating func show(_ e: PhotoEdit); mutating func commit(); mutating func set(_ e: PhotoEdit); mutating func reset(); mutating func undo(); mutating func redo(); var canUndo: Bool; var canRedo: Bool }`. `show` changes `current` with no step. `commit` makes 1 step from the last committed value, only if it changed. `set` is `show` then `commit`.

- [ ] **Step 1: Write the failing tests:** `originalIsOriginal`, `adjustmentIsClamped` (`150` reads `100`), `straightenIsClamped` (`-60` reads `-45`), `fourRotationsGiveTheOriginal`, `rotateMovesTheCrop` (crop `x: 0, y: 0, w: 0.5, h: 0.25` turned clockwise gives `x: 0.75, y: 0, w: 0.25, h: 0.5`), `flipHorizontalMovesTheCrop`, `twoFlipsGiveTheOriginal`, `portraitFrameTurnsFourThree` (`ratio` of a 30 × 40 frame is 0.75), `defaultFormatFollowsTheOriginal` (`JPG` → `.jpeg`, `HEIF` → `.heic`, `gif` → `.png`, `webp` → `.jpeg`), `dragIsOneUndoStep` (10 `show` calls, 1 `commit`, 1 `undo` gives `.original`), `commitWithoutChangeAddsNoStep`, `resetIsUndoable`, `newStepClearsRedo`, `historyKeepsAtMost100Steps`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter PhotoEditTests`. Expected: build fails (`PhotoEdit` not defined).
- [ ] **Step 3: Implement** the types in `PhotoEdit.swift`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): add the photo edit value and its history`.

### Task 4.2: Crop and straighten geometry

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/CropGeometry.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/CropGeometryTests.swift`

**Interfaces:**
- Consumes: `NormalizedRect` (task 4.1).
- Produces: `public enum CropHandle: CaseIterable, Sendable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move }`.
- Produces: `public enum CropGeometry` with pure static functions. `frameAspect` is width ÷ height of the frame in pixels.
  - `straightenScale(degrees: Double, width: Double, height: Double) -> Double`. The smallest scale so that the turned image covers the whole frame.
  - `drag(_ r: NormalizedRect, handle: CropHandle, dx: Double, dy: Double, ratio: Double?, frameAspect: Double, minSide: Double = 0.05) -> NormalizedRect`. Keeps the rect inside 0…1, keeps `ratio` (in pixels) when it is set, and keeps each side at least `minSide`. `.move` keeps the size.
  - `fit(_ r: NormalizedRect, ratio: Double?, frameAspect: Double) -> NormalizedRect`. The largest rect with `ratio` inside 0…1, centered on the center of `r`. `nil` returns `r`.

- [ ] **Step 1: Write the failing tests:** `zeroAngleNeedsNoScale` (1.0), `scaleCoversTheCorners` (for 10°, 4:3: the 4 frame corners turned by -10° and divided by the scale are inside the image), `dragStopsAtTheEdge`, `dragKeepsTheMinimumSide`, `dragKeepsTheRatio` (ratio 1, frame 4:3: `width × 4 == height × 3` within 1e-9), `moveKeepsTheSize`, `fitSquareOnLandscapeFrame` (frame 4:3, full rect gives `w: 0.75, h: 1`), `fitFreeformChangesNothing`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter CropGeometryTests`. Expected: build fails.
- [ ] **Step 3: Implement** `CropGeometry`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): add crop and straighten geometry`.

### Task 4.3: The Core Image pipeline

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/PhotoEditService.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/PhotoEditServiceTests.swift`
- Modify: `PicnestCore/Tests/PicnestCoreTests/Support/TestImages.swift`

**Interfaces:**
- Consumes: tasks 4.1 and 4.2, `ThumbnailService.thumbnail(at:maxPixel:)`.
- Produces: `public final class PhotoEditService: Sendable` with `init(thumbnails: ThumbnailService, images: ImageRepository, context: CIContext = CIContext())`. Task 4.4 adds the parameter `writer: ImageExportRepository = ImageExportRepository()` before `context`.
  - `static let previewMaxPixel = 1600`
  - `func preview(at url: URL) async -> CGImage?` (calls the thumbnail service).
  - `func apply(_ e: PhotoEdit, to image: CGImage, cropping: Bool = true) -> CGImage?`. Pure. `cropping: false` gives the whole frame after straighten, turns, and flips, for the crop tool.
  - `static func outputSize(of e: PhotoEdit, source: PixelSize) -> PixelSize`. Pure, rounded to whole pixels.
  - `static func filterValues(for e: PhotoEdit) -> (ev: Double, contrast: Double, saturation: Double, targetKelvin: Double)` (the table in "Adjustment map").
- Produces in `TestImages`: `writeQuadrants(to url: URL, type: UTType, width: Int, height: Int, orientation: Int = 1, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws`. Top left is red, top right green, bottom left blue, bottom right white, after the orientation. Also `static func color(at point: (x: Int, y: Int), in image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8)`. It reads in sRGB. Do not use `CGColorSpaceCreateDeviceRGB()` in new fixtures, because color management can shift a channel by more than 8.

- [ ] **Step 1: Write the failing tests.** Use a 40 × 20 PNG of quadrants. Read corners at 3 pixels in from each corner, with a tolerance of 8 per channel.
  - `originalEditKeepsSizeAndPixels`.
  - `rotateRightTurnsClockwise` (size 20 × 40; top-left corner is blue, top-right is red).
  - `rotateLeftTurnsCounterclockwise` (size 20 × 40; top-left is green). With the test above, this is Review Focus 4.
  - `flipHorizontalSwapsLeftAndRight` (size 40 × 20; top-left is green), `flipVerticalSwapsTopAndBottom`.
  - `cropLeftHalfKeepsRedAndBlue` (crop `x: 0, w: 0.5`; size 20 × 20).
  - `straightenFillsTheCorners` (5°: no corner pixel has alpha below 255).
  - `exifOrientationSixPreviewIsUpright` (JPEG with orientation 6 through `preview(at:)`: top-left is red; Review Focus 1).
  - `outputSizeMatchesApply` (5 edits; `outputSize` equals the size of `apply`).
  - `previewAndFullSizeHaveTheSameAspect` (same edit on 40 × 20 and 400 × 200: aspect within 1 pixel).
  - `positiveExposureMakesGrayBrighter`, `zeroSaturationMakesRedGray` (r, g, b within 8), `positiveWarmthMakesRedHigherThanBlue`, `positiveContrastSpreadsDarkAndLight`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter PhotoEditServiceTests`. Expected: build fails.
- [ ] **Step 3: Implement** the pipeline. Use `CIImage(cgImage:)`, `transformed(by:)`, `cropped(to:)`, and the filters in the table. Core Image has its origin at bottom left, and `NormalizedRect` has it at top left. Convert in 1 private helper. Call `clampedToExtent()` before the straighten transform. Make each crop rect integral, so no soft edge pixel stays.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): add the photo edit pipeline`.

### Task 4.4: Export an edited copy

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Repositories/ImageExportRepository.swift`
- Modify: `PicnestCore/Sources/PicnestCore/Repositories/ImageRepository.swift`, `Services/PhotoEditService.swift`, `Services/SortPlanner.swift` (`uniqueName` from `private` to `internal`)
- Create: `PicnestCore/Tests/PicnestCoreTests/PhotoExportTests.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/Support/FileFingerprint.swift` (move the SHA-256 helpers of `HashRepositoryTests` and `SortServiceTests` here; do not add a third copy)

**Interfaces:**
- Produces on `ImageRepository`: `func fullImage(at url: URL) -> (image: CGImage, properties: [CFString: Any])?`. It is full size and upright. Use `CGImageSourceCreateThumbnailAtIndex` at index 0 with 3 options: `kCGImageSourceCreateThumbnailFromImageAlways: true`, `kCGImageSourceCreateThumbnailWithTransform: true`, and `kCGImageSourceThumbnailMaxPixelSize` = the larger side. Without `FromImageAlways`, ImageIO returns the small EXIF thumbnail of a camera JPEG.
- Produces: `public struct ImageExportRepository: Sendable` with `init(fileOps: any FileOps = LocalFileOps())` and `func write(_ image: CGImage, to url: URL, format: ExportFormat, quality: Double, properties: [CFString: Any], replacing: Bool) throws`. It writes `.<name>.<UUID>.tmp` in the same folder. Then it calls `fileOps.move` (never overwrites), or `FileManager.replaceItemAt` when `replacing` is `true`. It removes the temp file on any error.
- Rule: the output keeps the color space of the source image (for example Display P3). If the source has none, use sRGB. Pass it to the `CIContext` output and to the `CGImage` that the writer gets.
- Produces: `public enum PhotoExportError: Error, Equatable, Sendable { case wouldReplaceOriginal, originalMissing, cannotRead, cannotWrite(String) }`.
- Produces: `public struct ProtectedFiles: Sendable { init(source: URL, mediaIDs: Set<MediaID>, otherPaths: [String]); func contains(_ url: URL) -> Bool }`. The init calls `canonicalKeyPath` on `source` 1 time. It keeps the ids lowercased. It does not touch the disk for each photo.
- Rule for `contains`: take the canonical path of the parent folder of `url`, plus the file name. If the result is inside the source folder, compare the NFC, lowercased relative path with the ids. Compare each of `otherPaths` (the `trashPath` values) the same way, lowercased.
- Produces on `PhotoEditService`: `static let exportQuality = 0.9`, `func exportCopy(of original: URL, edit: PhotoEdit, to destination: URL, format: ExportFormat, protected: ProtectedFiles) async throws -> URL` (runs off the caller's actor), and `static func uniqueName(_ name: String, in folder: URL) -> String` (calls `SortPlanner.uniqueName` with the names in the folder).
- Rule: `exportCopy` throws `wouldReplaceOriginal` when the destination is the original or `protected.contains(destination)`.
- Rule: the properties are those of the original, with orientation 1, the new pixel width and height, and no thumbnail dictionary. An image with alpha that goes to JPEG or HEIC is drawn on white first.

- [ ] **Step 1: Write the failing tests.** Each test that touches an original records its SHA-256, size, and modification date before, and checks all 3 after.
  - `exportWritesANewFileAndKeepsTheOriginal` (the copy decodes; its size is `outputSize`).
  - `exportToTheOriginalPathIsRefused` (`wouldReplaceOriginal`; Review Focus 2). Also with the name in other letter case (`img_2048.JPG`).
  - `exportOverAnotherSessionPhotoIsRefused`.
  - `exportOfOrientationSixIsUprightWithOrientationOne` (properties `Orientation` is 1 and width × height are swapped; Review Focus 1).
  - `exportKeepsTheExifDate` (use `TestImages.writeJPEG(exifDate:)`).
  - `exportInEachFormatHasItsType` (JPEG, HEIC, PNG: `CGImageSourceGetType` matches).
  - `failedWriteLeavesNoFile` (read-only folder: throws `cannotWrite`, and the folder has no new file).
  - `failedMoveRemovesTheTempFile` (a `FileOps` whose `move` throws after the temp file exists: throws `cannotWrite`, and the folder has no `.tmp`; Review Focus 5).
  - `exportOfAJPEGWithAnEmbeddedThumbnailIsFullSize` (write the fixture with `kCGImageDestinationEmbedThumbnail: true`; the copy has the full size).
  - `exportKeepsADisplayP3ColorSpace` (the copy has the color space name `CGColorSpace.displayP3`).
  - `exportWithMissingOriginalThrows` (`originalMissing`).
  - `replacingAnUnprotectedFileWorks` (an existing `a edited.jpg` is replaced, with no temp file left).
  - `uniqueNameAddsANumber` (`IMG edited.jpg` exists, so the result is `IMG edited 2.jpg`; NFD input gives the same result).
  - `alphaToJPEGHasAWhiteBackground`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter PhotoExportTests`. Expected: build fails.
- [ ] **Step 3: Implement** the repository, the 2 service methods, and `fullImage`. Move the hash helper and update its 2 old users.
- [ ] **Step 4: Run all core tests:** `swift test --package-path PicnestCore`. Expected: PASS, with `HashRepositoryTests` and `SortServiceTests` unchanged in result.
- [ ] **Step 5: Commit** `feat(core): export an edited copy and never replace a photo`.

### Task 4.5: Editor ViewModel

**Files:**
- Create: `Picnest/Editor/PhotoEditorViewModel.swift`
- Create: `PicnestTests/PhotoEditorViewModelTests.swift`
- Modify: `Picnest/App/AppEnvironment.swift` (make 1 `PhotoEditService` from the shared `ImageRepository` and `ThumbnailService`), `Picnest/App/CoreErrorMessages.swift` (text for each `PhotoExportError`), `Picnest/Localizable.xcstrings`

**Interfaces:**
- Consumes: tasks 4.1 to 4.4.
- Produces: `struct EditorPhoto: Identifiable, Hashable { let id: MediaID; let url: URL; let fileName: String }`.
- Produces: `enum EditorTool: CaseIterable { case crop, straighten, rotate, adjust }`.
- Produces: `@MainActor @Observable final class PhotoEditorViewModel` with `init(photos: [EditorPhoto], start: MediaID, service: PhotoEditService, protected: ProtectedFiles, chooseDestination: @escaping @MainActor (_ suggestedName: String, _ folder: URL, _ format: ExportFormat) async -> (URL, ExportFormat)?, revealURL: @escaping @MainActor (URL) -> Void, onClose: @escaping @MainActor () -> Void)`.
  - State: `tool`, `edit: PhotoEdit` (from the history), `previewImage: CGImage?`, `isShowingOriginal: Bool`, `isExporting: Bool`, `exportError: String?`, `lastExport: URL?`, `isConfirmingDiscard: Bool`, `current: EditorPhoto`, `positionText` ("1 of 5"), `canUndo`, `canRedo`, `hasChanges`.
  - Actions: `rotate(clockwise:)`, `flip(horizontal:)`, `setAspect(_:)` (calls `CropGeometry.fit`), `dragCrop(_ handle: CropHandle, dx: Double, dy: Double)`, `setStraighten(_:)`, `setAdjustment(_:_:)`, `endDrag()` (commits), `reset()`, `undo()`, `redo()`, `step(by offset: Int)`, `select(_ id: MediaID)`, `requestClose()`, `confirmDiscard()`, `export() async`, `revealLastExport()`.
- Rule: `step`, `select`, and `requestClose` set `isConfirmingDiscard` when `hasChanges`. `confirmDiscard` then does the waiting action.
- Rule: each change cancels the last preview task and starts 1 new task. `isShowingOriginal` shows the base preview with no edit.
- Rule: the suggested name is the catalog key `"%@ edited"` with the file stem, then `PhotoEditService.uniqueName`. The extension comes from `ExportFormat.defaultFormat(forExtension:)`.
- Copy (en, vi draft): **Edit Photo** / Chỉnh sửa ảnh; "Original stays unchanged" / "Ảnh gốc được giữ nguyên"; "Picnest never changes the original file. Export edited copy saves a new file." / "Picnest không bao giờ thay đổi tệp gốc. Xuất bản sao đã chỉnh sửa sẽ lưu một tệp mới."; **Reset** / Đặt lại; **Undo** / Hoàn tác; **Redo** / Làm lại; **Export edited copy** / Xuất bản sao đã chỉnh sửa; **Crop** / Cắt, "Trim and reframe" / "Cắt và căn khung"; **Straighten** / Làm thẳng, "Fix horizon" / "Chỉnh đường chân trời"; **Rotate** / Xoay, "Turn photo" / "Xoay ảnh"; **Adjust** / Điều chỉnh, "Tone and color" / "Tông màu và màu sắc"; **Aspect ratio** / Tỉ lệ khung hình; **Original** / Gốc; **Freeform** / Tự do; **Square** / Vuông; **Rotate & flip** / Xoay và lật; **Rotate left** / Xoay trái; **Rotate right** / Xoay phải; **Flip horizontal** / Lật ngang; **Flip vertical** / Lật dọc; **Adjustments** / Các điều chỉnh; **Exposure** / Phơi sáng; **Contrast** / Tương phản; **Warmth** / Độ ấm; **Saturation** / Độ bão hòa; "%@ · Original" / "%@ · Gốc"; "%@ · Edited" / "%@ · Đã chỉnh sửa"; "Edited copy will be exported separately" / "Bản sao đã chỉnh sửa sẽ được xuất riêng"; "%lld photos in this set" (plural) / "%lld ảnh trong bộ này"; "%1$lld of %2$lld" / "%1$lld / %2$lld"; "%@ edited" / "%@ đã chỉnh sửa"; **Show Original** / Xem ảnh gốc; "Discard your edits?" / "Bỏ các chỉnh sửa?"; "The edits are not saved. The original stays unchanged." / "Các chỉnh sửa chưa được lưu. Ảnh gốc được giữ nguyên."; **Discard Edits** / Bỏ chỉnh sửa; "Saved “%@”." / "Đã lưu “%@”."; "Choose another name. Picnest never replaces a photo of this folder." / "Hãy chọn tên khác. Picnest không bao giờ ghi đè ảnh trong thư mục này."; "The original photo is not in its folder now." / "Ảnh gốc không còn trong thư mục."; "Picnest could not read the photo." / "Picnest không đọc được ảnh."; "Picnest could not save the edited copy: %@" / "Picnest không lưu được bản sao đã chỉnh sửa: %@". Reuse the existing keys **Cancel** and **Show in Finder**.

- [ ] **Step 1: Write the failing tests.** Use `writeTestJPEG` from `PicnestTests/Support.swift` and a fake `chooseDestination`.
  - `testRotateIsOneUndoStep`, `testSliderDragIsOneUndoStepAfterEndDrag`, `testResetThenUndoBringsTheEditBack`, `testRedoAfterUndo`.
  - `testSquareAspectFitsTheCrop`.
  - `testStepWithChangesAsksBeforeDiscard` (`isConfirmingDiscard`, `current` unchanged; `confirmDiscard` moves on and gives `.original`).
  - `testStepWithoutChangesMovesAtOnce`, `testPositionText` ("2 of 3").
  - `testCloseWithChangesAsks`, `testCloseWithoutChangesCallsOnClose`.
  - `testSuggestedNameIsUniqueInTheFolder` (`a edited.jpg` exists, so the panel gets `a edited 2.jpg`).
  - `testCancelledPanelExportsNothing`.
  - `testExportOverTheOriginalShowsTheMessage` (fake panel returns the original URL; `exportError` is the catalog text; the original keeps its bytes).
  - `testExportKeepsTheEditAndSetsLastExport`.
  - `testPreviewUpdatesAfterAnEdit` (`waitUntil` the preview width changes after `rotate`).
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/PhotoEditorViewModelTests`. Expected: build fails.
- [ ] **Step 3: Implement.** Run `xcodegen generate` for the new folder. Add every string above with `en` and `vi`.
- [ ] **Step 4: Run the full app tests** and `python3 -I scripts/sync-string-catalog.py --check`. Expected: PASS, exit 0.
- [ ] **Step 5: Commit** `feat(editor): add the photo editor view model`.

### Task 4.6: Open the editor and route the keys

**Files:**
- Modify: `Picnest/Review/ReviewViewModel.swift`, `Picnest/Review/ReviewCommands.swift`, `Picnest/Review/SelectionBar.swift` (`PhotoContextMenu`), `Picnest/Review/InspectorView.swift`, `Picnest/Localizable.xcstrings`
- Create: `PicnestTests/EditorEntryTests.swift`

**Interfaces:**
- Consumes: task 4.5.
- Produces on `ReviewViewModel`: `canEdit(_ id: MediaID) -> Bool`, `openEditor(_ id: MediaID? = nil)`, `editor: PhotoEditorViewModel?` (read only), `closeEditor()`, `var isEditing: Bool`.
- Rule: `canEdit` is `true` only for a photo of kind `.image`, with no `.unreadable` state, outside Recently Deleted, while `canSortOrRescan` is `true`.
- Rule: the set is the selected images in grid order when 2 or more are selected. Else it is the visible images of the current item. `start` is the given id, or the anchor.
- Rule: `canSortOrRescan` is `false` while `isEditing`.
- Rule: `protected` is `ProtectedFiles(source:mediaIDs:otherPaths:)` with every `scan.media` id and every `trashPath`.
- Rule: while `isEditing`, the sidebar stays hidden. Remove the sidebar toggle (`.toolbar(removing: .sidebarToggle)`). A change of `selectedItem` while editing calls `editor.requestClose()` and keeps the old item until the close.
- Produces: `UndoRouting.route(firstResponderIsText: Bool, editorCanAct: Bool?, reviewCanAct: Bool) -> UndoRouting` with the new case `.editor`. `editorCanAct` is `nil` when no editor is open. The order is: text field, then editor, then review. An open editor that cannot act gives `.nothing`, never `.review`.
- Produces: menu **Image > Edit Photo** (⌘E), on only when `canEdit(anchor)`. Context menu **Edit Photo…** after **Open**. Inspector button **Edit** (`slider.horizontal.3`) for 1 photo. Copy: **Edit Photo** / Chỉnh sửa ảnh (reuse the task 4.5 key), **Edit Photo…** / Chỉnh sửa ảnh…, **Edit** / Chỉnh sửa, **Image** / Hình ảnh.

- [ ] **Step 1: Write the failing tests:** `testCanEditOnlyAReadableImage` (video, unreadable, and trashed give `false`), `testCanEditIsOffWhileFilesMove`, `testOpenEditorUsesTheSelectionAsTheSet`, `testOpenEditorWithOneSelectedUsesTheVisiblePhotos`, `testEditingTurnsOffSortRescanDoneAndStartOver` (Review Focus 3), `testCloseEditorKeepsTheSelection`, `testProtectedFilesHoldEveryPhoto` (a session photo, a trashed photo, and the NFD and upper-case name of a photo are protected; a new name is not), `testSidebarChangeWhileEditingAsksToClose`. In the same file: `testUndoRoutingOrder` (text before editor before review; an open editor that cannot act gives `.nothing`; Review Focus 3).
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/EditorEntryTests`. Expected: build fails.
- [ ] **Step 3: Implement** the ViewModel part and the routing. `ReviewCommands` reads the editor from `review?.editor`. Then add the menu item, the context menu item, and the inspector button.
- [ ] **Step 4: Run the full app tests** and the catalog check. Expected: PASS, exit 0. `AppDelegateTests` and the old undo tests stay green.
- [ ] **Step 5: Commit** `feat(editor): open the editor and route undo to it`.

### Task 4.7: The editor screen

**Files:**
- Create: `Picnest/Editor/PhotoEditorView.swift` (header, layout, keys), `Picnest/Editor/EditorCanvas.swift` (preview, crop frame, grid), `Picnest/Editor/EditorToolRail.swift`, `Picnest/Editor/EditorPanel.swift` (aspect, straighten, rotate and flip, adjustments), `Picnest/Editor/EditorFilmstrip.swift`
- Modify: `Picnest/Review/ReviewView.swift`, `Picnest/Design/Theme.swift`, `PicnestTests/ThemeTests.swift`, `Picnest/Localizable.xcstrings`

**Interfaces:**
- Consumes: tasks 4.5 and 4.6.
- Produces in `Theme`: `canvasBackground` (light `0xEFEAE7`, dark `0x141213`), `cropLine` (`0xFFFFFF` in both), `cropShade` (`0x000000` in both) with `Theme.cropShadeAlpha = 0.45`. In `Theme.Metrics`: `editorToolRail: CGFloat = 220`, `editorPanel: CGFloat = 300`, `filmstripHeight: CGFloat = 96`.
- Produces: `PhotoEditorView(model: PhotoEditorViewModel)`. `ReviewView.detail` shows it when `model.editor` is set, and sets the split view visibility to `.detailOnly`. It removes the sidebar toggle while the editor shows (task 4.6 rule).
- Layout (mockup 04), from top to bottom and left to right:
  - Header: **Edit Photo**, "Original stays unchanged" with an info button, **Reset**, **Undo**, **Export edited copy** (`.borderedProminent`).
  - Left rail: the 4 tools, each with icon, title, and subtitle.
  - Center: the canvas, then "IMG_2048.jpg · Original" or "· Edited", then "Edited copy will be exported separately".
  - Right panel, section 1 and 2: Aspect ratio (a menu that shows the output W × H), Straighten (slider -45…45, step 0.1).
  - Right panel, section 3 and 4: Rotate & flip (4 buttons), Adjustments (4 sliders, value at the right).
  - Bottom: the filmstrip, "N photos in this set", and ‹ "1 of 5" ›.
- The tool sets the canvas mode. **Crop** shows the whole frame with shade, a 3 × 3 grid, and 8 handles. **Straighten** shows the grid. **Rotate** and **Adjust** show the cropped result. A tool click scrolls the panel to its section.
- The toolbar shows **Back** (`chevron.left`, label "Back to Photos" / "Quay lại ảnh") and **Redo**. The account avatar and the tab bar are out (spec 6).
- Keys: ⌘Z and ⇧⌘Z go through task 4.6. Esc closes. ← and → step. ⌘R turns left, and ⌥⌘R turns right. ⇧⌘E exports.
- Hold **Show Original** to see the base image. Arrows and Esc work only when no text field and no slider has focus.
- Accessibility: each icon button has a label. Each slider has a value text ("+20"). The crop frame has an adjustable action: up makes it 5% larger, down makes it 5% smaller, around its center. With **Reduce Motion** on, no motion plays.

- [ ] **Step 1: Add the tokens.** Add `testCropLineIsVisibleOnShade` to `ThemeTests`: `cropLine` on `cropShade` has a contrast of at least 4.5 in both modes.
- [ ] **Step 2: Build** the 5 views. Reuse `ThumbnailImage` in the filmstrip. Convert crop drag points to 0…1 units in the canvas, then call `dragCrop`.
- [ ] **Step 3: Hook** the view into `ReviewView`, the discard dialog, the export error alert, and the "Saved" note with **Show in Finder**.
- [ ] **Step 4: Manual check I (editing).** Open a landscape JPEG, a portrait HEIC with EXIF orientation 6, and a PNG with alpha. On each, crop square, straighten 10°, turn right, flip, and set each slider. Export, then open the copy in Preview. It looks like the editor preview. Press ⌘Z until the photo is `.original`. Run `shasum -a 256` on the original before and after. The hash is the same.
- [ ] **Step 5: Manual check J (layout).** In `en` and `vi`, Light and Dark, at 1000 × 680, no text is cut, and the panel scrolls. Compare with mockup 04. Write the differences in a list.
- [ ] **Step 6: Manual check K (keys and VoiceOver).** Press ⌘Z in the editor after a category move in the library. Only the edit undoes. Press ⇧⌘R: nothing happens. VoiceOver reads every button and slider.
- [ ] **Step 7: Run the full app tests** and the catalog check. Expected: PASS, exit 0. Commit `feat(editor): add the photo editor screen`.

### Task 4.8: Docs and final pass

**Files:** `docs/dictionary.md`, `docs/specs/2026-11-01-ui-redesign-design.md`, `BUILD.md` (only if a new check needs a step), this plan.

- [ ] **Step 1: Dictionary.** Add Photo Editor, Edited copy, Export edited copy, Original. Each says that it changes no file of the source folder, except the new copy where the user saves it.
- [ ] **Step 2: Spec 4.5.** Write the entry points (inspector, context menu, ⌘E; Quick Look has no button), the export formats, and the rule that protects session photos. Link to this plan section.
- [ ] **Step 3: Search for color literals** as in task 2.8 step 1. Expected: nothing in `Picnest/Editor`.
- [ ] **Step 4: Run both test suites and the catalog check.** Expected: PASS, exit 0.
- [ ] **Step 5: Merge phase 4** into `ui-redesign`. Tick the Status line.

### Open questions for the owner (phase 4)

Each has a default in the tasks above. Change a default before its task starts.

1. Where the save panel opens first (task 4.5). Default: the folder of the original. A copy there shows as a new photo after the next rescan. Other choice: `~/Pictures`.
2. Metadata of the copy (task 4.4). Default: keep EXIF, date, and GPS. Other choice: remove GPS location.
3. Export formats and quality (task 4.4). Default: JPEG, HEIC, PNG, quality 0.9, format of the original. Other choice: a quality slider in the panel.
4. The filmstrip (task 4.7). Default: in scope, with the selection or the visible photos as the set. Other choice: 1 photo only, no filmstrip.
5. Entry points (task 4.6). Default: inspector, context menu, ⌘E. Double-click stays Quick Look. Other choice: Return or double-click opens the editor.
6. An animated GIF (task 4.4). Default: the editor uses the first frame and exports PNG. Other choice: no edit for a GIF.

---

## Phase 5: Layout Editor

Sub-branch: `feature/ui-redesign/phase-5-layout-editor`. Spec: section 4.6, sections 2.2 (Moodboard is a non-goal), 3, 6, 7 (call 4). Mockup: `design/picnest-ui-05-layout-editor.png`. Design text: section 9.
Core tests use Swift Testing (`@Test func name()`). App tests use Swift Testing too (`@Test func testName()`, as in `PicnestTests/EditorEntryTests.swift`). Read `PhotoEdit.swift` (`EditHistory`), `PhotoExport.swift` (`ProtectedFiles`), `ImageExportRepository.swift`, `ImageRepository.swift`, `PhotoEditService.swift`, `Picnest/Editor/*.swift`, `ReviewViewModel.swift` (section "Photo editor"), `ReviewView.swift`, and `ReviewCommands.swift` before you start.

### Facts from the code

- The photo editor opens as the detail of `ReviewView`. `ReviewViewModel.editor: PhotoEditorViewModel?` drives it. `isEditing` turns off Sort, Rescan, **Done**, and **Start Over…** through `canSortOrRescan`.
- While `isEditing`, `ReviewView` sets the split view to `.detailOnly` and removes the sidebar toggle. A sidebar change calls `editor.requestClose()` and keeps the old item (`itemAfterClose`).
- `UndoRouting.route(firstResponderIsText:editorCanAct:reviewCanAct:)` sends ⌘Z to a text field, then the editor, then the review. `ReviewCommands` reads `review?.editor`.
- `EditHistory` is typed to `PhotoEdit`. Its rules (`show`, `commit`, `undo` drops a value that is not committed, limit 100) fit any value.
- `ImageExportRepository.write` writes a temp file in the destination folder, then moves it into place. Only an `CGImageDestination` can encode the temp file today. A PDF needs the same temp-and-move rule.
- `ProtectedFiles.contains` refuses session photos, Trash files, and links to them. `PhotoEditService.isSameFile` is private.
- `EditorSavePanel.choose` is typed to `ExportFormat` (JPEG, HEIC, PNG).
- `ImageRepository.thumbnail(for:maxPixel:)` downsamples with ImageIO and caches in an `NSCache` of 200 MB. `fullImage(at:)` decodes the full size. A layout export must not decode full size.
- `Session` holds favorites and collections. `ReviewService` is its only writer. `CollectionService.rekey` and `prune` keep ids correct at **Done**, folder rename, and rescan.
- No menu item uses ⌘L today (`grep -rn 'keyboardShortcut("l"' Picnest` is empty).

### Key decisions

**Scope.**

| In this phase | Out of this phase |
|---------------|-------------------|
| Contact sheet (task 5.2), then Collage (task 5.10) | Moodboard (spec 2.2). The Layout picker shows 2 items |
| Paper size, orientation, presets, spacing, background, captions | Free placement, rotation of a photo in a cell, text styles |
| Undo, Redo, 1 draft per session that saves by itself | Many named layout projects |
| Export PNG (1 file per page) and PDF (1 file, all pages) | Print dialog, JPEG export, Share button |
| Preview mode, zoom, page steps | Photo edits inside a cell (crop, filters) |

**Units.** The layout works in PDF points (1/72 inch), origin top left. `PaperSize` stores millimetres. Convert with `mm × 72 / 25.4`. A4 landscape is 841.8898 × 595.2756 pt. PNG pixels are `round(pt / 72 × dpi)`. A4 landscape at 300 dpi is 3508 × 2480 px. At 150 dpi it is 1754 × 1240 px.

**The document.** `LayoutDocument` is 1 value type in Core. It holds the kind, the paper, the orientation, the preset or template, margin, spacing, background, captions, title, note, and the ordered photo ids. Undo uses the generic history (task 5.1). The engine (`LayoutEngine`) is pure: document plus photo sizes in, page and cell rects out. The renderer draws only what the engine returns. The on-screen page and the export use the same renderer, so the preview is the export.

**Contact sheet and collage.** A contact sheet shows each photo whole (aspect fit). It has a grid preset (columns × rows) and makes as many pages as the photos need. A collage fills each cell (aspect fill, centered crop). It has 1 page and 1 template. Photos past the template's cell count are not drawn. The panel says how many are used.

**Captions.** **Include captions** shows the footer: title at the left, note at the right (mockup 05: "Coastline", "Weekend away"). A contact sheet also has **File names under photos**. Caption text is user data, so the renderer draws it as given. The text color comes from the background (dark text on light, light text on dark).

**Page colors are data, not theme.** The page, its background swatches, and its text never follow Light or Dark. `LayoutBackground` holds 5 fixed sRGB colors (mockup 05: white, cream, light gray, blush, charcoal). The editor chrome around the page uses `Theme`.

**Draft.** `Session.layoutDraft: LayoutDocument?` (decodes with `decodeIfPresent`). Reason: phase 3 rule, 1 writer of `session.json`, and `rekey` and `prune` already run there. The ViewModel saves the draft 1 second after the last change, and at close. Saving the draft is not a review undo step. **Start Over** loses the draft, as for collections.

**Where it opens.** The layout editor uses the photo editor host: the detail column, `.detailOnly`, no sidebar toggle, Sort and Rescan off, ⌘Z to the editor. Task 5.6 turns `editor: PhotoEditorViewModel?` into `activeEditor: ActiveEditor?` with 2 cases. Nothing in the host is copied.

**Leaving.** The draft saves by itself, so **Back** and Esc close with no Discard dialog. A sidebar change while the layout editor is open closes it and then selects the item.

**Entry points.** **Create Layout…** in: the photo context menu (the selection), the sidebar context menu of a category and of a collection, the more menu of `PhotoSetHeaderView`, and the menu **Image > Create Layout…** (⌘L, the selection, or the current category or collection when nothing is selected). When a draft with photos exists, an alert asks: **Continue Layout**, **Start New**, **Cancel**. **Start New** replaces the draft.

**Export.**
- Formats: PNG and PDF. The save panel is `EditorSavePanel`, made generic (task 5.5). The panel opens in the last layout folder, else `~/Pictures`. Reason: a layout in the source folder shows as a new photo after the next rescan.
- Suggested name: the layout title, else "Contact Sheet" or "Collage", then `PhotoEditService.uniqueName`.
- PNG with more than 1 page writes `<stem> 1.png`, `<stem> 2.png`, and so on. If any of these names exists, except the name the user confirmed in the panel, the export stops before it writes and shows the name.
- Every destination goes through `ProtectedFiles.contains`. A protected name fails with `PhotoExportError.wouldReplaceOriginal`, and nothing is written.
- Resolution: **Standard** (150 dpi) or **High** (300 dpi, default) in the panel section **Export**. PNG uses it for pixels. PDF uses it to cap the pixels of each embedded photo.
- A photo file that is gone at export time fails the export with `originalMissing`. Nothing is written.

**Memory.** The renderer asks an image provider for 1 photo at a time, at the pixel size its cell needs (`LayoutEngine.neededPixels`), never full size. The export provider decodes without the shared cache (new `ImageRepository.downsampled(at:maxPixel:)`). The preview provider uses `ThumbnailService` (cached, `steps`). Each page draws inside its own `autoreleasepool`. The PDF writes page by page to the temp file.

### Phase 5 Review Focus

Each line has a test or a check in the named task.

1. A4 landscape: the page is 841.8898 × 595.2756 pt, the PDF media box matches within 0.01 pt, and the 300 dpi PNG is 3508 × 2480 px. Tasks 5.2 and 5.5.
2. The user types the name of a session photo (for example `IMG_0001.PNG` for `img_0001.png`) in the save panel and clicks **Replace**. The export fails with a message, and the photo keeps its SHA-256, size, and modification date. Task 5.5.
3. A contact sheet of 1,000 photos at 300 dpi exports with no full-size decode. The provider never gets a `maxPixel` larger than the cell needs. Tasks 5.4 and 5.5.
4. The layout editor is open. ⌘Z undoes a layout step, not a category move. ⇧⌘R and **Done** are off. Task 5.6.
5. A draft survives **Done** (files renamed) and a rescan: ids follow `rekey`, and removed files drop out. Task 5.3.
6. The page looks the same in Light and Dark mode. Only the chrome changes. Task 5.9 (check M).

### Task 5.1: Layout types and the generic history

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Domain/Layout.swift`
- Modify: `PicnestCore/Sources/PicnestCore/Domain/PhotoEdit.swift` (`EditHistory`)
- Create: `PicnestCore/Tests/PicnestCoreTests/LayoutTypesTests.swift`
- Test: `PicnestCore/Tests/PicnestCoreTests/PhotoEditTests.swift` (unchanged, must stay green)

**Interfaces:**
- Produces: `public struct History<Value: Hashable & Sendable>: Sendable` with `init(_ original: Value, limit: Int = 100)` and the members of today's `EditHistory` (`current`, `show`, `commit`, `set`, `undo`, `redo`, `canUndo`, `canRedo`, `hasPendingChange`). `reset()` sets the `original` of the init. `public typealias EditHistory = History<PhotoEdit>` plus `extension History where Value == PhotoEdit { init(limit: Int = 100) }`, so phase 4 code does not change.
- Produces: `public struct LayoutRect: Sendable, Hashable { var x, y, width, height: Double }` (points, top-left origin) with `maxX`, `maxY`.
- Produces: `public struct PageSize: Sendable, Hashable { var width, height: Double }` (points).
- Produces: `public enum PaperSize: String, CaseIterable, Sendable, Codable { case a4, a3, a5, letter }` with `millimetres: (width: Double, height: Double)` (portrait: A4 210 × 297, A3 297 × 420, A5 148 × 210, Letter 215.9 × 279.4) and `func pageSize(_ o: PageOrientation) -> PageSize`.
- Produces: `public enum PageOrientation: String, CaseIterable, Sendable, Codable { case landscape, portrait }`.
- Produces: `public enum LayoutKind: String, CaseIterable, Sendable, Codable { case contactSheet, collage }`.
- Produces: `public struct GridPreset: Sendable, Hashable, Codable { var columns, rows: Int }` with `static let presets: [GridPreset]` = 3 × 2, 2 × 3, 4 × 2, 4 × 3, 5 × 4 (the first 3 are mockup 05). `var perPage: Int`.
- Produces: `public enum CollageTemplate: String, CaseIterable, Sendable, Codable` (cases in task 5.10; this task adds only `case twoByTwo`, so the type exists).
- Produces: `public enum LayoutBackground: String, CaseIterable, Sendable, Codable { case white, cream, gray, blush, charcoal }` with `var rgb: (r: Double, g: Double, b: Double)` and `var textRGB` (sRGB). Read the 5 swatch colors from mockup 05.
- Produces: `public enum ExportResolution: Int, CaseIterable, Sendable, Codable { case standard = 150, high = 300 }`.
- Produces: `public struct LayoutDocument: Sendable, Hashable, Codable` with `kind`, `paper`, `orientation`, `grid: GridPreset`, `template: CollageTemplate`, `margin: Double` (default 36, clamped 0…72), `spacing: Double` (default 24, clamped 0…72), `background`, `showsCaptions: Bool` (default `true`), `showsFileNames: Bool` (default `false`), `title: String`, `note: String`, `photoIDs: [MediaID]`, `resolution: ExportResolution` (default `.high`). `static func new(photos: [MediaID], title: String) -> LayoutDocument` gives a contact sheet, A4, landscape, 3 × 2. Decode with `decodeIfPresent` and the defaults, so a later field does not break an old draft.
- Produces: `public enum LayoutExportFormat: String, CaseIterable, Sendable { case png, pdf }` with `utType`, `fileExtension`.
- Produces: `public protocol ExportFileFormat: CaseIterable, Hashable, Sendable { var utType: UTType { get }; var fileExtension: String { get } }`. `ExportFormat` and `LayoutExportFormat` conform.

- [ ] **Step 1: Write the failing tests:** `a4LandscapeIsExactInPoints` (841.8898 × 595.2756 within 1e-4), `a4PortraitSwapsTheSides`, `letterIsSixHundredTwelveBySevenNinetyTwo`, `marginAndSpacingAreClamped` (`-5` reads 0, `100` reads 72), `newDocumentIsAContactSheetOnA4Landscape`, `documentRoundTripsThroughJSON`, `oldDraftWithoutResolutionDecodes` (JSON without `resolution` gives `.high`), `presetsStartWithTheMockupGrids` (`3×2`, `2×3`, `4×2`), `genericHistoryUndoesAnyValue` (`History<Int>`: `set(1)`, `set(2)`, `undo` gives 1, `reset` gives 0 and is undoable).
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter LayoutTypesTests`. Expected: build fails (`LayoutDocument` not defined).
- [ ] **Step 3: Implement** `Layout.swift`. Change `EditHistory` into `History<Value>` and the typealias. Do not copy the history code.
- [ ] **Step 4: Run all core tests.** Expected: PASS, with `PhotoEditTests` unchanged.
- [ ] **Step 5: Commit** `feat(core): add layout types and a generic history`.

### Task 5.2: Contact sheet geometry

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/LayoutEngine.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/LayoutEngineTests.swift`

**Interfaces:**
- Consumes: task 5.1.
- Produces: `public enum ImageFit: Sendable { case fit, fill }`.
- Produces: `public struct LayoutCell: Sendable, Hashable { var frame: LayoutRect; var imageArea: LayoutRect; var caption: LayoutRect?; var mediaID: MediaID?; var index: Int; var fit: ImageFit }`. `imageArea` is `frame` less the caption band. `mediaID` is nil for an empty cell.
- Produces: `public struct LayoutPage: Sendable, Hashable { var size: PageSize; var cells: [LayoutCell]; var footer: LayoutRect? }`.
- Produces: `public enum LayoutEngine` with pure static functions and constants `footerHeight = 40`, `captionHeight = 14`:
  - `pages(for d: LayoutDocument) -> [LayoutPage]`. Contact sheet: `ceil(photoIDs.count / perPage)` pages, at least 1. The last page keeps its empty cells (the screen shows them; the renderer skips them).
  - `gridCells(in content: LayoutRect, columns: Int, rows: Int, spacing: Double) -> [LayoutRect]` (row by row).
  - `contentRect(page: PageSize, margin: Double, footer: Bool, spacing: Double) -> (grid: LayoutRect, footer: LayoutRect?)`. With a footer, the grid ends `spacing` above it.
  - `imageRect(source: PixelSize, in area: LayoutRect, fit: ImageFit) -> LayoutRect`. Fit centers inside. Fill covers and centers (the renderer clips to `area`).
  - `pixelSize(of page: PageSize, dpi: Int) -> PixelSize` (`round(pt / 72 × dpi)`).
  - `neededPixels(for area: LayoutRect, source: PixelSize, fit: ImageFit, dpi: Int) -> Int`. The longest side, in source pixels, that the drawn rect needs at `dpi`. Never above the longest source side.
- Rule: a spacing or margin that leaves a cell under 1 pt makes the engine use spacing 0 for that page. It never returns a negative size.

- [ ] **Step 1: Write the failing tests.** Use A4 landscape, margin 36, spacing 24, 3 × 2, tolerance 1e-3 (Review Focus 1).
  - `a4LandscapeThreeByTwoCellSize` (each frame is 240.6299 × 249.6378).
  - `a4LandscapeCellOrigins` (cell 0 at 36, 36; cell 4 at 300.6299, 309.6378; cell 5 `maxX` is 805.8898, `maxY` is 559.2756).
  - `gapsEqualTheSpacing` (each horizontal and vertical gap is 24).
  - `footerTakesItsBandAndOneGap` (captions on: cell height 217.6378; footer at y 519.2756, height 40, width 769.8898).
  - `fileNameBandShrinksTheImageArea` (image area height = frame height - 14).
  - `sevenPhotosOnThreeByTwoMakeTwoPages` (page 2 has 1 filled cell and 5 empty cells), `noPhotosMakeOneEmptyPage`.
  - `fitLandscapePhotoInACell` (4000 × 3000 in cell 0: 240.6299 × 180.4724 at y 36 + 34.5827).
  - `fillCoversTheArea` (the rect contains the area and keeps 4:3).
  - `a4LandscapePixelsAt300And150` (3508 × 2480, 1754 × 1240), `letterLandscapeAt300` (3300 × 2550).
  - `neededPixelsIsCappedBySource` (a 640 × 480 photo in a 3508-px-wide cell gives 640), `neededPixelsForAFitCell` (4000 × 3000 in cell 0 at 300 dpi: 240.6299 / 72 × 300 = 1002.6, rounded up to 1003).
  - `hugeSpacingNeverGivesANegativeSize` (spacing 72, margin 72, 5 × 4 on A5).
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter LayoutEngineTests`. Expected: build fails.
- [ ] **Step 3: Implement** `LayoutEngine` for `.contactSheet`. `.collage` returns 1 page with no cells until task 5.10.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): add contact sheet geometry`.

### Task 5.3: The draft in the session

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/LayoutService.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/LayoutServiceTests.swift`
- Modify: `Domain/Session.swift`, `Services/ReviewService.swift` (`rekey`, new method), `Services/ScanService.swift` (`runRescan`)
- Test: `SessionRepositoryTests.swift`, `ReviewServiceTests.swift`, `ScanServiceTests.swift`

**Interfaces:**
- Produces: `Session.layoutDraft: LayoutDocument?` (new `init` parameter, default `nil`; `decodeIfPresent`).
- Produces: `public enum LayoutService` with pure static functions on `LayoutDocument`:
  - `add(_ ids: [MediaID], to d: inout LayoutDocument, at index: Int? = nil) -> Bool` (no repeats, keeps order).
  - `remove(_ ids: [MediaID], from d: inout LayoutDocument) -> Bool`.
  - `move(_ id: MediaID, to index: Int, in d: inout LayoutDocument) -> Bool` and `swap(_ a: MediaID, _ b: MediaID, in d: inout LayoutDocument) -> Bool`.
  - `rekey(_ map: [MediaID: String], in s: inout Session)` and `prune(keeping ids: Set<MediaID>, in s: inout Session)`.
- Produces on `ReviewService`: `saveLayoutDraft(_ d: LayoutDocument?)`. It saves when the value changed. It pushes no undo step. `rekey(_:)` calls `LayoutService.rekey`. `runRescan` calls `LayoutService.prune` next to `CollectionService.prune`.

- [ ] **Step 1: Write the failing tests:** `addKeepsOrderWithoutRepeats`, `addAtIndexInserts`, `moveAndSwapReorder`, `removeDropsIDs`, `rekeyMovesDraftPhotos`, `pruneDropsMissingDraftPhotos`. In `SessionRepositoryTests`: `oldSessionWithoutLayoutDraftDecodes`, add a draft to `sessionWithEveryFieldRoundTrips`. In `ReviewServiceTests`: `layoutDraftIsSavedAndIsNotAnUndoStep`, `applyOrganizeReKeysTheLayoutDraft` (Review Focus 5). In `ScanServiceTests`: `rescanDropsDraftPhotosOfRemovedFiles`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all core tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): keep a layout draft in the session`.

### Task 5.4: The page renderer

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/LayoutRenderer.swift`
- Modify: `PicnestCore/Sources/PicnestCore/Repositories/ImageRepository.swift`
- Create: `PicnestCore/Tests/PicnestCoreTests/LayoutRendererTests.swift`
- Modify: `PicnestCore/Tests/PicnestCoreTests/Support/TestImages.swift` (only if a solid-color helper is missing; reuse `writeQuadrants` and `color(at:in:)`)

**Interfaces:**
- Consumes: tasks 5.1 and 5.2.
- Produces on `ImageRepository`: `func downsampled(at url: URL, maxPixel: Int) -> CGImage?`. Upright, not cached. It calls the private `decode`. Do not copy it.
- Produces: `public typealias LayoutImageProvider = @Sendable (MediaID, Int) async -> CGImage?` (id, max pixel).
- Produces: `public struct LayoutRenderer: Sendable` with `init(sizes: @Sendable (MediaID) async -> PixelSize?)` and:
  - `func draw(_ page: LayoutPage, document d: LayoutDocument, fileNames: [MediaID: String], in ctx: CGContext, dpi: Int, images: LayoutImageProvider) async`. It fills the background, then for each cell with a photo asks `images` for `neededPixels`, draws in `imageRect` clipped to `imageArea`, and releases the image. Then the file-name captions and the footer text with Core Text (system font, 9 pt and 14/10 pt, color `background.textRGB`, 1 line, tail truncation).
  - `func image(of page: LayoutPage, document d: LayoutDocument, fileNames: [MediaID: String], dpi: Int, images: LayoutImageProvider) async -> CGImage?`. A bitmap in sRGB, 8 bits, pixel size `LayoutEngine.pixelSize`. The preview and the PNG export use it.
- Rule: the context uses a top-left transform once (`translateBy(0, height)`, `scaleBy(1, -1)`) in 1 private helper. Images draw through a second flip, so they are upright.
- Rule: a cell whose provider returns nil draws nothing (background shows). The export decides about missing files (task 5.5).

- [ ] **Step 1: Write the failing tests.** Render at 72 dpi (1 pt = 1 px). Read pixels with `TestImages.color(at:in:)`, tolerance 8.
  - `pageImageHasThePixelSizeOfThePaper` (A4 landscape at 72 dpi: 842 × 595).
  - `backgroundFillsTheGapsAndMargins` (charcoal at (10, 10) and at the center of the first vertical gap).
  - `photoFillsItsFitRect` (a red 400 × 300 image: red at the center of cell 0; background 5 px above its fit rect).
  - `fillModeClipsToTheArea` (a red image with `.fill`: red at each corner of the area, background 2 px outside).
  - `quadrantImageIsUpright` (`writeQuadrants`: the top-left of the drawn rect is red; Core Graphics flips are a known trap).
  - `emptyCellsDrawNothing`.
  - `missingImageLeavesTheBackground`.
  - `providerGetsOnlyTheNeededPixels` (records each `maxPixel`; none is above `neededPixels`; Review Focus 3).
  - `pageLooksTheSameInEachAppearance` (render with `NSAppearance` `.aqua` and `.darkAqua` current; the 2 bitmaps are equal; Review Focus 6).
  - `downsampledIsUprightAndNotCached` (orientation 6 JPEG is upright; a second call returns a new object).
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter LayoutRendererTests`. Expected: build fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): render layout pages`.

### Task 5.5: Export PNG and PDF

**Files:**
- Create: `PicnestCore/Sources/PicnestCore/Services/LayoutExportService.swift`
- Modify: `Repositories/ImageExportRepository.swift`, `Domain/PhotoExport.swift`, `Services/PhotoEditService.swift` (move `isSameFile` into `ProtectedFiles`)
- Create: `PicnestCore/Tests/PicnestCoreTests/LayoutExportTests.swift`
- Modify: `Picnest/Editor/EditorSavePanel.swift` (generic), `Picnest/Review/ReviewViewModel.swift` (call site)

**Interfaces:**
- Produces on `ImageExportRepository`: `func writeFile(to url: URL, replacing: Bool, encode: (URL) throws -> Void) throws`. It owns the temp name, the move or `replaceItemAt`, and the clean-up. `write(_:to:format:…)` calls it. Do not copy the temp logic.
- Produces on `ProtectedFiles`: `func refuses(_ destination: URL, original: URL?) -> Bool` (`contains`, or the same file as `original`). `PhotoEditService.exportCopy` calls it. The private `isSameFile` moves here.
- Produces: `public final class LayoutExportService: Sendable` with `init(thumbnails: ThumbnailService, images: ImageRepository, writer: ImageExportRepository = ImageExportRepository())` and:
  - `func previewImage(of page: LayoutPage, document: LayoutDocument, fileNames: [MediaID: String], maxPixel: Int, source: URL) async -> CGImage?` (thumbnail provider; dpi from `maxPixel` and the page width).
  - `func export(_ d: LayoutDocument, fileNames: [MediaID: String], source: URL, to url: URL, format: LayoutExportFormat, protected: ProtectedFiles) async throws -> [URL]`. Runs off the caller's actor, and passes cancellation on (same pattern as `exportCopy`).
  - `static func pageURLs(for url: URL, pageCount: Int, format: LayoutExportFormat) -> [URL]` (1 URL for PDF or 1 page; else `<stem> 1.png` …).
- Rule: before any write, check every photo file exists (`originalMissing`), every page URL against `protected.refuses` (`wouldReplaceOriginal`), and every page URL except `url` for an existing file (`cannotWrite` with the name).
- Rule: PDF uses `CGContext(consumer:mediaBox:)` on the temp URL in `writeFile`, 1 `beginPDFPage` per page, media box = page size in points. Photos draw at `document.resolution`.
- Produces in the app: `EditorSavePanel.choose<F: ExportFileFormat>(suggestedName: String, folder: URL, format: F, title: (F) -> String) async -> (URL, F)?`. The photo editor passes its 3 formats. The layout passes PNG and PDF.

- [ ] **Step 1: Write the failing tests.** Each test that has a session photo records its SHA-256, size, and modification date (`FileFingerprint`) before and checks all 3 after.
  - `a4LandscapePNGIs3508By2480` (`CGImageSourceCopyPropertiesAtIndex` width and height; Review Focus 1).
  - `a4LandscapePDFMediaBoxIsExact` (`CGPDFDocument` page 1 `.mediaBox` is 841.8898 × 595.2756 within 0.01).
  - `pdfHasOnePagePerSheet` (7 photos on 3 × 2: 2 pages).
  - `multiPagePNGWritesNumberedFiles` (`Sheet 1.png`, `Sheet 2.png`).
  - `multiPagePNGStopsWhenAPageNameExists` (`Sheet 2.png` exists: throws, and no file is new).
  - `exportOverASessionPhotoIsRefused` (`IMG_0001.PNG` for `img_0001.png`; Review Focus 2). Also a symlink to a session photo.
  - `exportWithAMissingPhotoWritesNothing` (`originalMissing`).
  - `failedPDFWriteLeavesNoTempFile` (a `FileOps` whose `move` throws).
  - `thousandPhotosExportWithoutFullDecode` (1,000 photo ids that point to 4 fixture files of 4000 × 3000; a spy provider records each `maxPixel`; no value is above the `neededPixels` of its cell; Review Focus 3). Mark it `.timeLimit(.minutes(2))`.
  - In `PhotoExportTests`: all old tests stay green after the `writeFile` and `refuses` moves.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter LayoutExportTests`. Expected: build fails.
- [ ] **Step 3: Implement** the core part. Then make `EditorSavePanel` generic and update its 1 call site.
- [ ] **Step 4: Run all core tests and the full app tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): export layouts to PNG and PDF and never replace a photo`.

### Task 5.6: One host for both editors

**Files:**
- Create: `Picnest/Editor/ActiveEditor.swift`
- Modify: `Picnest/Review/ReviewViewModel.swift`, `Picnest/Review/ReviewCommands.swift`, `Picnest/Review/ReviewView.swift`, `Picnest/Editor/PhotoEditorViewModel.swift` (conformance only)
- Test: `PicnestTests/EditorEntryTests.swift`

**Interfaces:**
- Produces: `@MainActor protocol EditorSession: AnyObject { var canUndo: Bool { get }; var canRedo: Bool { get }; func undo(); func redo(); func requestClose() }`. `PhotoEditorViewModel` conforms with no change of behavior.
- Produces: `enum ActiveEditor { case photo(PhotoEditorViewModel), layout(LayoutEditorViewModel) }` with `var session: any EditorSession`. Task 5.7 adds the type `LayoutEditorViewModel`. In this task, add only the `.photo` case.
- Produces on `ReviewViewModel`: `private(set) var activeEditor: ActiveEditor?`. `editor: PhotoEditorViewModel?` becomes a computed property, so phase 4 tests do not change. `isEditing` is `activeEditor != nil`. `closeEditor()` clears `activeEditor`. The `selectedItem` guard calls `activeEditor?.session.requestClose()`.
- Produces: `ReviewCommands` routes undo with `editorCanAct: review?.activeEditor?.session.canUndo` and acts on `session`.
- Produces: `ReviewView.detail` switches on `activeEditor`. `.detailOnly` and the removed sidebar toggle follow `isEditing`.

- [ ] **Step 1: Write the failing test** `testActiveEditorDrivesIsEditing` (open the photo editor: `activeEditor` is `.photo`, `canSortOrRescan` is false; close: nil).
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/EditorEntryTests`. Expected: build fails.
- [ ] **Step 3: Implement** the refactor. Run `xcodegen generate`.
- [ ] **Step 4: Run the full app tests.** Expected: PASS, with every phase 4 test unchanged.
- [ ] **Step 5: Commit** `refactor(editor): one host for the editors`.

### Task 5.7: Layout editor ViewModel

**Files:**
- Create: `Picnest/Editor/LayoutEditorViewModel.swift`
- Create: `PicnestTests/LayoutEditorViewModelTests.swift`
- Modify: `Picnest/Editor/ActiveEditor.swift` (add `.layout`), `Picnest/App/AppEnvironment.swift` (1 `LayoutExportService` from the shared `ImageRepository` and `ThumbnailService`), `Picnest/App/CountText.swift`, `Picnest/Localizable.xcstrings`

**Interfaces:**
- Consumes: tasks 5.1 to 5.6.
- Produces: `struct LayoutPhoto: Identifiable, Hashable { let id: MediaID; let fileName: String }`.
- Produces: `struct LayoutSourceOption: Identifiable, Hashable { let id: String; let title: String; let photos: [LayoutPhoto] }`. The left panel lists **All Photos**, each category, and each collection. The ViewModel gets them from `ReviewViewModel`; it does not read the session.
- Produces: `@MainActor @Observable final class LayoutEditorViewModel: EditorSession` with `init(document: LayoutDocument, sources: [LayoutSourceOption], startSource: String, service: LayoutExportService, source: URL, protected: ProtectedFiles, fileNames: [MediaID: String], saveDraft: @escaping @MainActor (LayoutDocument?) -> Void, chooseDestination: @escaping @MainActor (_ name: String, _ folder: URL, _ format: LayoutExportFormat) async -> (URL, LayoutExportFormat)?, revealURL: @escaping @MainActor (URL) -> Void, onClose: @escaping @MainActor () -> Void, defaults: UserDefaults = .standard)`.
  - State: `document` (from `History<LayoutDocument>`), `pages: [LayoutPage]`, `pageIndex`, `pageImage: CGImage?`, `selectedCell: Int?`, `zoom: Double` (0.25…4, default "fit"), `isPreviewing`, `isExporting`, `exportError: String?`, `lastExport: [URL]`, `sourceID`, `searchText`, `canUndo`, `canRedo`.
  - Text: `pageText` ("Page 1 of 3"), `countText` ("6 photos", plural), `usedText` (collage: "Uses 4 of 6 photos"), `paperText` ("A4 (297 × 210 mm)", follows the orientation), `spacingText` ("24 pt").
  - Actions: `setKind`, `setPaper`, `setOrientation`, `setGrid`, `setTemplate`, `setBackground`, `setCaptions(_:)`, `setFileNames(_:)`, `setTitle`, `setNote`, `setResolution`, `setSpacing` and `setMargin` (slider pattern of the photo editor: `beginDrag`, `endDrag`, idle commit), `add(_ ids: [MediaID], at: Int?)`, `remove(_ ids:)`, `removeSelected()`, `move(_ id:, to:)`, `swap`, `selectCell`, `step(page:)`, `zoomIn`, `zoomOut`, `zoomToFit`, `togglePreview`, `undo`, `redo`, `requestClose`, `export() async`, `revealLastExport()`.
- Rule: each committed change saves the draft after 1 second (`draftDelay`, a test hook), and `requestClose` saves at once, then calls `onClose`. No discard dialog.
- Rule: each change recomputes `pages` and starts 1 new preview task that cancels the last one, as in `PhotoEditorViewModel.refreshPreview`. The preview size is the canvas width × 2, capped at 2400 px.
- Rule: a text field change (title, note) is 1 undo step after the idle delay, as a slider.
- Rule: the export folder is `UserDefaults` key `"layoutExportFolder"`, else `~/Pictures`. A good export saves the folder.
- Copy (en / vi draft): **Create Layout** / Tạo bố cục; **Layout** / Bố cục; **Contact sheet** / Bảng ảnh thu nhỏ; **Collage** / Ghép ảnh; **Paper size** / Khổ giấy; "%1$@ (%2$@ × %3$@ mm)" / "%1$@ (%2$@ × %3$@ mm)" (paper name, width, height); **Orientation** / Hướng giấy; **Landscape** / Ngang; **Portrait** / Dọc; **Layout presets** / Mẫu bố cục; **Spacing** / Khoảng cách; **Margin** / Lề; "%@ pt" / "%@ pt"; **Background** / Nền; **White** / Trắng; **Cream** / Kem; **Gray** / Xám; **Blush** / Hồng nhạt; **Charcoal** / Than chì; **Include captions** / Thêm chú thích; **File names under photos** / Tên tệp dưới ảnh; **Title** / Tiêu đề; **Note** / Ghi chú; **Photos** / Ảnh; "Search photos" / "Tìm ảnh"; "Drag to add to layout" / "Kéo để thêm vào bố cục"; "%lld photos" (reuse the existing plural key); "Page %1$lld of %2$lld" / "Trang %1$lld / %2$lld"; "Uses %1$lld of %2$lld photos" / "Dùng %1$lld trên %2$lld ảnh"; **Preview** / Xem trước; **Export** / Xuất; **Export** section **Resolution** / Độ phân giải; **Standard (150 dpi)** / Tiêu chuẩn (150 dpi); **High (300 dpi)** / Cao (300 dpi); **Remove from Layout** / Xóa khỏi bố cục; **Zoom In** / Phóng to; **Zoom Out** / Thu nhỏ; **Fit Page** / Vừa trang; "Saved %lld files." (plural) / "Đã lưu %lld tệp."; "A file named “%@” already exists. Choose another name." / "Đã có tệp tên “%@”. Hãy chọn tên khác."; **Continue Layout** / Tiếp tục bố cục; **Start New** / Tạo mới; "Continue your last layout?" / "Tiếp tục bố cục trước?"; "Your last layout has %lld photos." (plural) / "Bố cục trước có %lld ảnh."; **Create Layout…** / Tạo bố cục…; "The layout saves by itself. Export makes a PNG or PDF file. Your photos do not change." / "Bố cục tự lưu. Xuất tạo tệp PNG hoặc PDF. Ảnh của bạn không thay đổi.". Reuse **Undo**, **Redo**, **Cancel**, **Show in Finder**, "Back to Photos", and the export error texts of task 4.5. The names **PNG** and **PDF** are `shouldTranslate: false`.

- [ ] **Step 1: Write the failing tests.** Use `writeTestJPEG` from `PicnestTests/Support.swift`, a fake `chooseDestination`, and a fake `saveDraft` that records values.
  - `testSettingChangeIsOneUndoStep` (orientation, then undo), `testSpacingDragIsOneUndoStepAfterEndDrag`, `testTitleTypingIsOneUndoStep`.
  - `testPagesFollowPhotoCount` (7 photos on 3 × 2: `pageText` "Page 1 of 2").
  - `testAddDropsRepeatsAndRemoveSelectedRemoves`, `testMoveReorders`.
  - `testPaperTextFollowsOrientation` ("A4 (297 × 210 mm)" then "A4 (210 × 297 mm)").
  - `testCollageUsedText` (template of 4 cells, 6 photos: "Uses 4 of 6 photos").
  - `testDraftSavesAfterTheDelayAndOnClose` (`draftDelay` 10 ms; `requestClose` saves at once and calls `onClose`; no confirm).
  - `testSourceSearchFiltersTheLeftPanel` (case and diacritic insensitive, as task 1.1).
  - `testExportSuggestsTheTitleAndAUniqueName` (`Summer trip.pdf` exists, so the panel gets `Summer trip 2.pdf`).
  - `testExportOverAPhotoShowsTheMessage` (`exportError` is the catalog text; the photo keeps its bytes).
  - `testExportRemembersTheFolder`, `testCancelledPanelExportsNothing`.
  - `testPreviewUpdatesAfterAChange` (`waitUntil` the page image width changes after `setOrientation`).
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/LayoutEditorViewModelTests`. Expected: build fails.
- [ ] **Step 3: Implement.** Run `xcodegen generate`. Add every string above with `en` and `vi`.
- [ ] **Step 4: Run the full app tests** and `python3 -I scripts/sync-string-catalog.py --check`. Expected: PASS, exit 0.
- [ ] **Step 5: Commit** `feat(layout): add the layout editor view model`.

### Task 5.8: Open the layout editor

**Files:**
- Modify: `Picnest/Review/ReviewViewModel.swift`, `ReviewCommands.swift`, `SelectionBar.swift` (`PhotoContextMenu`), `SidebarView.swift`, `PhotoSetHeaderView.swift` (more menu items), `ReviewView.swift` (the continue alert), `Picnest/Localizable.xcstrings`
- Create: `PicnestTests/LayoutEntryTests.swift`

**Interfaces:**
- Consumes: tasks 5.3, 5.6, 5.7.
- Produces: `enum LayoutOrigin: Hashable { case selection, category(CategoryID), collection(CollectionID) }`.
- Produces on `ReviewViewModel`: `canCreateLayout(from: LayoutOrigin) -> Bool`, `requestLayout(from: LayoutOrigin)`, `askingToContinueLayout: LayoutOrigin?`, `continueLayout()`, `startNewLayout()`, `var layoutEditor: LayoutEditorViewModel?` (computed from `activeEditor`).
- Rule: the photos are the readable images of the origin, not trashed, in grid order (selection), category order, or collection member order. `canCreateLayout` needs `canSortOrRescan` and at least 1 such photo.
- Rule: when `session.layoutDraft` has 1 or more photos, `requestLayout` sets `askingToContinueLayout`. **Continue Layout** opens the draft. **Start New** opens `LayoutDocument.new(photos:title:)`. The title is the category display name, the collection name, or empty for a selection.
- Rule: `protected` is built as in `openEditor`. Extract 1 private helper `protectedFiles()` and call it from both.
- Produces: menu **Image > Create Layout…** (⌘L). The origin is the selection when it is not empty, else the current category or collection. Off for other items with no selection. Context menu **Create Layout…** after **Edit Photo…**. Sidebar context menu **Create Layout…** on categories and collections. The same item in the more menu of `PhotoSetHeaderView`.

- [ ] **Step 1: Write the failing tests:** `testLayoutFromSelectionUsesGridOrder`, `testLayoutFromCategoryLeavesOutVideoAndTrashed`, `testLayoutFromCollectionUsesMemberOrder`, `testCreateLayoutIsOffWhileFilesMove`, `testDraftAsksToContinue`, `testStartNewReplacesTheDraft`, `testOpeningLayoutTurnsOffSortAndDone`, `testUndoGoesToTheLayoutEditor` (`UndoRouting` with an open layout editor that cannot act gives `.nothing`; Review Focus 4), `testSidebarChangeClosesTheLayoutAndSelects` (no dialog; draft saved; the new item shows).
- [ ] **Step 2: Run** `xcodebuild test … -only-testing:PicnestTests/LayoutEntryTests`. Expected: build fails.
- [ ] **Step 3: Implement** the ViewModel part, then the menus and the alert. Add strings with `vi`.
- [ ] **Step 4: Run the full app tests** and the catalog check. Expected: PASS, exit 0.
- [ ] **Step 5: Commit** `feat(layout): open the layout editor from a selection, category, or collection`.

### Task 5.9: The layout editor screen

**Files:**
- Create: `Picnest/Layout/LayoutEditorView.swift` (header, layout, keys), `Picnest/Layout/LayoutPhotoPanel.swift` (left), `Picnest/Layout/LayoutCanvas.swift` (page, cell overlays, drop targets), `Picnest/Layout/LayoutSettingsPanel.swift` (right), `Picnest/Layout/LayoutBottomBar.swift`, `Picnest/Layout/LayoutBackground+Color.swift` (`LayoutBackground` to `Color` for the swatches)
- Modify: `Picnest/Review/ReviewView.swift`, `Picnest/Design/Theme.swift`, `PicnestTests/ThemeTests.swift`, `Picnest/Localizable.xcstrings`

**Interfaces:**
- Consumes: tasks 5.7 and 5.8.
- Produces in `Theme`: `pageShadow` (`0x000000` in both, alpha `Theme.pageShadowAlpha = 0.12`), `cellOutline` = `accent`. Reuse `canvasBackground` (task 4.7) for the area around the page. In `Theme.Metrics`: `layoutPhotoPanel: CGFloat = 240`, `layoutSettingsPanel: CGFloat = 300` (reuse `editorPanel` if the value is the same; do not add a second constant with the same value).
- Produces: `LayoutEditorView(model: LayoutEditorViewModel, library: ReviewViewModel)`. `ReviewView.detail` shows it for `.layout`.
- Layout (mockup 05):
  - Header: **Create Layout**, the title under it (click to edit), **Undo**, **Redo**, **Preview** (`eye`), **Export** (`.borderedProminent`, a menu with **PNG…** and **PDF…**, ⇧⌘E).
  - Left panel: **Photos**, search field, source menu, grid of `ThumbnailImage` (reuse), "N photos", "Drag to add to layout". Each tile drags `MediaID`s (reuse the transfer type of the grid). Double-click adds.
  - Center: the page image on `canvasBackground` with `pageShadow`. Overlays: cell outlines, the selected cell in `cellOutline`, empty cells with a dashed outline. Overlays hide in **Preview**.
  - Right panel: **Layout** (2 buttons; no Moodboard), **Paper size** menu, **Orientation**, **Layout presets** (3 drawn previews per row; grid for a contact sheet, template for a collage), **Spacing** slider (0…72, step 1, value at the right), **Margin** slider, **Background** (5 round swatches with a ring on the chosen one), **Include captions** with **Title** and **Note** fields, **File names under photos** (contact sheet only), **Export** with **Resolution**.
  - Bottom bar: "N photos", ‹ "Page 1 of 3" ›, zoom −, value, +, **Fit Page**, and the right panel toggle.
- The left panel and the right panel hide in **Preview**. Esc leaves Preview first, then closes.
- Drag and drop: a drop on a cell inserts at that index. A drop on the page with no cell appends. A drag of a cell onto another cell swaps the 2 photos.
- Keys: ⌘Z, ⇧⌘Z through task 5.6. ← → move the selected cell. ⌥← ⌥→ move the photo 1 place. ⌫ removes the selected photo from the layout. ⌘+ ⌘- ⌘0 zoom. Page Up and Page Down step pages. Keys work only when no text field has focus.
- Accessibility: each cell is 1 element, label "Photo 3 of 6, IMG_2048.jpg", or "Empty cell 4". Actions: **Move Earlier**, **Move Later**, **Remove from Layout**. Each swatch has its color name as label and the selected trait. Sliders have a value text ("24 pt"). With **Reduce Motion** on, zoom and panel changes do not animate.

- [ ] **Step 1: Add the tokens.** Add `testPageCaptionContrastOnEachBackground` to `ThemeTests`: for each `LayoutBackground`, `textRGB` on `rgb` has a contrast of at least 4.5 (use `RGB.contrast`; do not copy the formula into Core).
- [ ] **Step 2: Build** the 5 views. Convert drop points to cells with `LayoutPage.cells` and the zoom. Do not compute layout geometry in a view.
- [ ] **Step 3: Hook** the view into `ReviewView`, the export error alert, and the "Saved" note with **Show in Finder**.
- [ ] **Step 4: Manual check L (output).** Make a contact sheet of 7 photos, A4 landscape, 3 × 2, captions on. Export PDF and PNG at High. Open them in Preview: 2 PDF pages; 2 PNG files of 3508 × 2480 (`sips -g pixelWidth -g pixelHeight`). Run `shasum -a 256` on 3 source photos before and after. The hashes are the same.
- [ ] **Step 5: Manual check M (layout and themes).** In `en` and `vi`, Light and Dark, at 1000 × 680, no text is cut, and the right panel scrolls. The page is the same in Light and Dark (Review Focus 6). Compare with mockup 05. Write the differences in a list.
- [ ] **Step 6: Manual check N (keys, drag, VoiceOver).** Drag 2 photos in from the left panel. Swap 2 cells. Press ⌘Z after a category move in the library: only the layout step undoes. ⇧⌘R does nothing. VoiceOver reads each cell, swatch, and slider.
- [ ] **Step 7: Run the full app tests** and the catalog check. Expected: PASS, exit 0. Commit `feat(layout): add the layout editor screen`.

### Task 5.10: Collage

**Files:**
- Modify: `PicnestCore/Sources/PicnestCore/Domain/Layout.swift`, `Services/LayoutEngine.swift`, `Picnest/Layout/LayoutSettingsPanel.swift`, `Picnest/Localizable.xcstrings`
- Test: `LayoutEngineTests.swift`, `LayoutRendererTests.swift`, `LayoutExportTests.swift`

**Interfaces:**
- Produces: `public indirect enum SplitNode: Sendable, Hashable { case cell; case row([SplitNode]); case column([SplitNode]) }`. Children share the space equally, with `spacing` between them.
- Produces: `CollageTemplate` cases `twoByTwo`, `heroLeft` (`row([cell, column([cell, cell])])`), `heroTop` (`column([cell, row([cell, cell, cell])])`), `twoOverThree` (`column([row([cell, cell]), row([cell, cell, cell])])`), with `var root: SplitNode` and `var cellCount: Int`.
- Produces: `LayoutEngine.split(_ node: SplitNode, in rect: LayoutRect, spacing: Double) -> [LayoutRect]` (depth first, left to right, top to bottom). `pages(for:)` for `.collage`: 1 page, cells from `template.root`, `fit: .fill`, no file-name band.
- Copy (en / vi draft): **Two by two** / Hai nhân hai; **Large left** / Ảnh lớn bên trái; **Large top** / Ảnh lớn phía trên; **Two over three** / Hai trên ba.

- [ ] **Step 1: Write the failing tests.** A4 landscape, margin 36, spacing 24, tolerance 1e-3.
  - `heroLeftGeometry` (left cell 36, 36, 372.9449 × 523.2756; right cells at x 432.9449, height 249.6378 each).
  - `twoOverThreeGapsEqualTheSpacing`, `cellCountMatchesTheTemplate`.
  - `collageHasOnePageAndIgnoresExtraPhotos` (6 photos on `twoByTwo`: 4 cells with ids, 1 page).
  - `collageCellsUseFill` and, in `LayoutRendererTests`, `collageFillHasNoBackgroundInsideACell`.
  - In `LayoutExportTests`: `collagePDFHasOnePage`.
- [ ] **Step 2: Run** `swift test --package-path PicnestCore --filter "LayoutEngineTests|LayoutRendererTests|LayoutExportTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the templates and the split. Show the templates in **Layout presets** for a collage. Add the strings with `vi`.
- [ ] **Step 4: Run all core tests, the full app tests, and the catalog check.** Expected: PASS, exit 0.
- [ ] **Step 5: Commit** `feat(layout): add collage templates`.

### Task 5.11: Docs and final pass

**Files:** `docs/dictionary.md`, `docs/specs/2026-11-01-ui-redesign-design.md`, `BUILD.md` (only if a new check needs a step), this plan.

- [ ] **Step 1: Dictionary.** Add Layout Editor, Layout, Contact sheet, Collage, Layout draft, Paper size. Each says that it changes no photo. Example: "Contact sheet: a page of photos in a grid, each shown whole. Export makes a PNG or PDF file. No photo changes."
- [ ] **Step 2: Spec 4.6.** Write the entry points (context menu, sidebar, header, ⌘L), the draft rule (1 draft in `Session`), the formats and resolutions, the default folder, and the rule that protects session photos. Link to this plan section.
- [ ] **Step 3: Search for color literals** as in task 2.8 step 1. Expected: nothing in `Picnest/Layout` outside `LayoutBackground+Color.swift`, which reads Core data.
- [ ] **Step 4: Run both test suites and the catalog check.** Expected: PASS, exit 0.
- [ ] **Step 5: Merge phase 5** into `ui-redesign`. Tick the Status line. Ask the owner before any merge into `main`.

### Open questions for the owner (phase 5)

Each has a default in the tasks above. Change a default before its task starts.

1. Layout storage (task 5.3). Default: 1 draft per folder session, in `session.json`. **Start Over** loses it. Other choice: named layout projects (design text 9 "save as project").
2. Default export folder (task 5.7). Default: the last layout folder, else `~/Pictures`. Reason: a file in the source folder shows as a photo after a rescan. Other choice: the source folder.
3. PNG for more than 1 page (task 5.5). Default: 1 file per page, `<name> 1.png`. Other choice: only the current page.
4. Captions (task 5.1). Default: **Include captions** shows a footer with title and note. File names under photos are a separate switch, off. Other choice: 1 switch for both.
5. Resolution (task 5.5). Default: High, 300 dpi. A4 landscape PNG is 3508 × 2480 px. Other choice: 600 dpi for print shops.
6. Spacing unit (task 5.9). Default: points ("24 pt"), as for print. The mockup shows "24 px".
7. Margin control (task 5.9). Default: a **Margin** slider, 36 pt. The mockup has no margin control. Other choice: a fixed margin.
8. Collage templates (task 5.10). Default: 4 templates. Other choice: more templates, or a free grid.
