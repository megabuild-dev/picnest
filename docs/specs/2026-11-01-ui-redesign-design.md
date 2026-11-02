---
id: picnest-ui-redesign-design
title: Picnest UI Redesign, Themes, and Languages
type: spec
status: active
tags: [picnest, ui, theme, localization, swiftui]
links:
  - "[[2026-10-21-macos-app-design]]"
  - "[[dictionary]]"
  - "[[2026-11-01-ui-redesign-plan]]"
  - "[[BUILD]]"
  - "[[CONTRIBUTING]]"
---

# Picnest UI Redesign, Themes, and Languages

## 1. Intent

The owner approved a new UI design for Picnest. The design is in `design/`: 5 mockups (`picnest-ui-01` to `05`) and the text file `PicNest — Đề xuất thiết kế UI_UX tổng thể.md`.
This spec turns that design into work for the existing SwiftUI app.

Picnest is an open source project. Contributors and users need 3 things from the first release of the new UI:

- A light theme, a dark theme, and a **System** setting that follows macOS.
- Interface text that a contributor can translate without a code change.
- A UI that other people can restyle by changing 1 place.

## 2. Goals, non-goals, anti-goals

### 2.1 Goals

- The app matches the 5 approved mockups for layout, color, and wording.
- The user picks **System**, **Light**, or **Dark** in Settings. The app changes at once, with no restart.
- English is the default and source language. Vietnamese is the first added language.
- A contributor adds a language by editing 1 string catalog and following a short guide.
- Every old feature keeps working. The tests that exist now keep passing.

### 2.2 Non-goals

- Cloud sync, accounts, or any network use for photos.
- Photo Tags, Notes, and Location (shown in mockup 01). The app has no data for them. See section 6.
- Moodboard layouts (shown in mockup 05).
- iOS, iPadOS, or App Store release.
- Languages that read right to left. The layout must not block them, but this release does not test them.

### 2.3 Anti-goals

These results make the work a failure, even if it runs:

- A restyle that changes how the app sorts, moves, or trashes files.
- A string in the UI that a translator cannot reach.
- A color in a view that does not come from the design tokens.
- A dark theme with text that the user cannot read.
- A Vietnamese screen that cuts text or breaks the layout.

## 3. Decisions of the owner

- Use the approved design.
- English is the default language.
- Add Vietnamese next. Add more languages later.
- The app has System, Light, and Dark appearance modes.
- Category names stay in English, as data. The user renames them. CLIP prompts stay in English.
- The filter for photos the user decided is named **Chosen by you**.
- The sidebar is the full sidebar of mockups 01 and 02.

## 4. Phases

Each phase ends with a working app that passes its tests. Phases 0 to 2 are the core release. Phases 3 to 5 add new features. The owner can stop after any phase.

| Phase | Name | Result |
|-------|------|--------|
| 0 | Foundation | Design tokens, appearance setting, string catalog, English and Vietnamese text |
| 1 | App shell | New sidebar, toolbar, and inspector. Old screens run inside them |
| 2 | Screens | Welcome, Scan, Library, Needs Review, Category, Duplicates, Sort, and Settings match the mockups |
| 3 | Favorites, Collections, Recently Deleted | New sidebar items with data |
| 4 | Photo Editor | Crop, straighten, rotate, flip, adjust, export an edited copy |
| 5 | Layout Editor | Contact sheet and collage, export to PNG and PDF |

### 4.1 Phase 0: Foundation

**Design tokens.** One Swift file defines all colors, corner radii, and spacing. Each color has a light value and a dark value.
The mockups set these colors: warm neutral background, charcoal text, berry or coral accent, green for confirmed, amber for needs review, red for destructive actions.
`ReviewStyle.swift` moves into the token file. No view uses a color literal after this phase.
The values come from the mockups. The builder reads the PNG files and picks exact values. Light and dark values need a contrast check of at least 4.5:1 for body text. Check white text on the accent buttons first.

**Appearance.** A new setting has 3 values: `system` (default), `light`, `dark`. The app saves it in `UserDefaults`.
The builder applies it with `NSApp.appearance` (`nil` for `system`). `preferredColorScheme` is the other option. It may not reach the Settings window, alerts, and Sparkle windows. The builder tests both and picks one that works in the check of section 8.
Settings opens with ⌘, and has an **Appearance** control. This is the first item of the new Settings window (section 10 of the design text).

**Languages.**
- The app target gets 1 String Catalog (`Localizable.xcstrings`). Source language is `en`. `PicnestCore` gets no catalog. It stays free of UI text.
- Every UI string goes through the catalog. SwiftUI literals (`Text("...")`) already do. Strings built in code use `String(localized:)`.
- A helper or a ViewModel that gives text to a view returns `LocalizedStringKey` or `LocalizedStringResource`, never `String`. Reason: a plain `String` passed to `Text` is not in the catalog. `SidebarView.row(…, "All photos", …)` is an example to fix.
- Strings with a number use plural variations in the catalog, not `if count == 1`.
- `SortMessages.swift` moves to the catalog. It already maps each `SortError` to text in the app target. Core errors keep this pattern. A core error with no mapping falls back to `localizedDescription`, so the builder adds a mapping for each one.
- Dates, sizes, and numbers use `FormatStyle`. They follow the language and region of the user.
- `project.yml` already sets `developmentLanguage: en`. Add `vi` to the known regions. Make sure the generated project builds the `.xcstrings` file as a resource and extracts strings from Swift code. XcodeGen 2.46.0 is installed.
- The app follows the macOS language by default. Settings has a **Language** control with **System**, **English**, **Tiếng Việt**. It writes `AppleLanguages` and asks the user to restart the app. This is the decision of the builder (section 7).

**Contributor guide.** `CONTRIBUTING.md` gets a section: how to add a language, how to test it, and how to use pseudo-languages in Xcode.

**Checks.** A test makes sure that:
- Every key in the catalog has a `vi` value that is not empty and is `translated`.
- A script reads the built catalog and fails CI when a `vi` value is missing, `new`, or `stale`.

### 4.2 Phase 1: App shell

Replace the current `NavigationSplitView` layout in `ReviewView.swift` with the layout of the mockups.

- **Sidebar** (220 to 250 pt). Mockups 01 and 02 show the full sidebar. Mockup 03 shows a short version, with Categories as 1 item. This spec uses the full sidebar. Mockup 03 shows the Category screen, not the sidebar. Sections: Library (All Photos, Needs Review, Favorites), Collections, Categories, Tools (Duplicates), and Recently Deleted at the bottom. Each item shows a count. Favorites, Collections, and Recently Deleted show only after phase 3. Before that, the shell leaves them out.
- **Toolbar.** Back and forward, title with photo count, search field, grid and list toggle, thumbnail size slider, sort menu, and an inspector toggle.
- **Inspector.** Right panel. Can show or hide. Shows the selected photo, its facts, and the main action. Content changes with the selection (photo, category, none).
- Old names change to the design names: **All photos** stays **All Photos**, **Not sure** becomes **Needs Review**, **Changed by you** becomes a filter chip named **Chosen by you**. Update the spec and dictionary names in the same phase.
- Sidebar drag of photos to a category keeps working.

### 4.3 Phase 2: Screens

| Screen | Mockup | Main points |
|--------|--------|-------------|
| Welcome | none (design text section 1) | Choose Folder button, drop zone, Recent folders as cards, privacy line |
| Scan | none (design text section 2) | Progress, found count, Cancel text that says nothing is deleted, summary at the end |
| Library | 01 | Filter chips All, Needs review, Chosen by you. Grid. Inspector with facts and **Move to…** |
| Needs Review | 02 | Banner, 3 filters, confidence badge on tiles, selection bar, suggestion panel in the inspector |
| Category | 03 | Header with icon and count, **Rename**, **Add Photos**, **Edit Category** dialog (name, icon, folder), link **Create a collection instead** |
| Duplicates | none (design text section 6) | Tabs Exact copies and Similar photos. Side-by-side groups. Clear **Keep** choice |
| Sort sheet | none (design text section 7) | Same logic as now. New style. Folder preview |
| Settings | none | Appearance, Language, Updates. Other items from the design text come later |

Rules for this phase:
- A screen change must not change a ViewModel rule. If a rule must change, write it in the plan first.
- **Edit Category** shows the folder name. The **Change…** button for the folder works only if `CategoryFolderService` already supports a rename. If it does not, show the folder as read only. This is a decision of the builder (section 7).
- Add empty, loading, and error states for each screen.

### 4.4 Phase 3: Favorites, Collections, Recently Deleted

- **Favorite** is a flag on a photo. It does not move a file.
- **Collection** is a named group of photos. It does not move a file. The UI uses a different icon and word from Category.
- New types go in `PicnestCore/Domain/` first. `Session` gets 2 new fields. They decode with `decodeIfPresent`, so old `session.json` files still open (same method as `trashed`).
- The key is `MediaID`, the path of the file in the source folder. The data is in `Session`.
- 4 events lose the data: a rename in Finder, a rescan after a Move sort, a rescan while a photo is in the Trash, and **Start Over**. See [[2026-11-01-ui-redesign-plan#Key decision: the photo key]].
- `CollectionService` owns the rules. `SessionRepository` saves the data. Views and ViewModels never write `session.json` directly.
- **Recently Deleted** lists the photos in `Session.trashed`. It offers **Put Back**, which uses `TrashService.putBack`.
- **Create a collection instead** in the Category dialog opens the new-collection flow.

### 4.5 Phase 4: Photo Editor

- Opens from 3 places: the **Edit** button in the inspector, **Edit Photo…** in the context menu, and the shortcut ⌘E. Quick Look has no edit button.
- Has tools Crop, Straighten, Rotate, Adjust (exposure, contrast, warmth, saturation).
- The edit never changes the original file. The only output is **Export edited copy**.
- Use Core Image. Keep the edit as a value type with a **Reset** and an **Undo**.
- The app does not save the edit recipe in this release. Reason: the design text says to export a copy when a safe recipe store does not exist.
- The editor shows the text "Original stays unchanged".
- Export formats are JPEG, HEIC, and PNG, with quality 0.9. The default format follows the original: HEIC for HEIC, PNG for PNG, TIFF, and GIF, and JPEG for all others. An animated GIF uses its first frame.
- The copy keeps the EXIF data, the date, and the GPS location of the original.
- The save panel opens in the folder of the original. A copy there shows as a new photo after the next rescan.
- **Protected files:** an export never replaces a photo of the session or a file in the Trash. If the user picks such a name, the app shows a message and writes nothing. This includes a symlink or hard link to such a file.
- While the editor is open, Sort, Rescan, and Start Over are off.
- Details are in [[2026-11-01-ui-redesign-plan#Phase 4: Photo Editor]].

### 4.6 Phase 5: Layout Editor

- **Entry points:** **Create Layout…** is in 4 places. They are the photo context menu, the sidebar context menu, the header menu, and the menu **Image**. The sidebar and header menus work for a category or a collection. The shortcut ⌘L uses the selection. If nothing is selected, ⌘L uses the current category or collection.
- First output: **Contact sheet**. Second output: **Collage**. Mockup 05 shows Contact sheet selected. This order is a decision of the builder (section 7).
- Controls: paper size (A3, A4, A5, Letter), orientation, presets, spacing, margin, background, captions.
- **Draft rule:** `Session` holds 1 layout draft for each source folder, in `session.json`. The app saves it 1 second after the last change and when the editor closes. **Start Over** deletes it. If a draft with photos exists, a dialog shows **Continue Layout**, **Start New**, and **Cancel**.
- **Formats:** PNG and PDF. A PNG file holds 1 page, so a layout with 3 pages makes 3 PNG files. A PDF file holds all pages.
- **Resolutions:** **Standard** is 150 dpi. **High** is 300 dpi, and it is the default. An A4 landscape PNG at 300 dpi is 3508 × 2480 px. The PDF uses the resolution to cap the pixels of each embedded photo.
- **Default folder:** the save panel opens in the last layout folder, or in `~/Pictures` if none exists. Reason: a file in the source folder shows as a new photo after the next rescan.
- **Protected files:** an export never replaces a photo of the session or a file in the Trash. This includes a symlink or hard link to such a file. If the user picks such a name, the app shows a message and writes nothing.
- Undo and Redo work on layout steps. A collage uses only the photos that fit its template cells. The panel shows how many photos it uses.
- Details are in [[2026-11-01-ui-redesign-plan#Phase 5: Layout Editor]].

## 5. Constraints

- macOS 15 and later. Swift 6. SwiftUI. XcodeGen (`project.yml`) stays the source of the Xcode project.
- Layers stay as they are: View, ViewModel, Service, Repository in `PicnestCore`. A View holds no business logic.
- Search for an existing component before a new one. A repeated UI part becomes 1 shared view.
- No network call for photos or embeddings (anti-goal of the main spec).
- Work follows the branch rules: 1 branch `feature/ui-redesign`, 1 sub-branch per phase, merge after each phase.
- Doc files follow OKF 2.0 and ASD-STE100. Update `docs/dictionary.md` when a term changes.
- Phase 0 changes section 1.4 of [[2026-10-21-macos-app-design]]. The line "Interface languages other than English" must go.

## 6. Mockup items outside this release

| Item | Where | Reason |
|------|-------|--------|
| Location in the inspector | Mockup 01 | Needs a GPS read from photo metadata. No data in the app today |
| Tags and Notes | Mockup 01 | No storage and no search for them |
| Moodboard | Mockup 05 | The design text says "later" |
| Account avatar | Mockup 04 | The app has no account |
| Edit tabs Library, Edit, Favorites in the title bar | Mockup 04 | Conflicts with the sidebar of mockups 01 to 03. The editor opens as a view in the main window |

The inspector shows these fields: name, category, date, dimensions, file size, confidence.

## 7. Calls made by the author

The owner did not decide these. Change any of them before the plan starts.

1. **Phase order.** Foundation first, then shell, then screens, then new features. Reason: theme and language touch every view. Doing them last means doing every view twice.
2. **Language setting.** Follow macOS by default. Add an in-app override that needs a restart. A live switch needs a custom bundle. That adds risk and gives little.
3. **Edit Category folder change.** Read only if the service cannot rename.
4. **Contact sheet before Collage.**
5. **Chosen by you** is the filter name. The owner chose it (section 3). It avoids a clash with the Photo Editor in phase 4. The mockup text "Edited by me" changes to it.
6. **Tags, Notes, Location** are out of this release.
7. **Mockup 04** is a view in the main window, not a tab bar.
8. **Settings** has only Appearance, Language, and Updates now.
9. **Vietnamese text** is a first draft by the builder. A native speaker must review it before release.

## 8. Success criteria

- The 5 screens match the mockups in layout and color. The owner checks them by eye.
- In **Light**, **Dark**, and **System**, every screen is readable. The owner switches macOS appearance with the app open and sees the change at once.
- With the system language set to Vietnamese, no English text shows, except file names, proper names, and the names of categories that came from data (section 3).
- Switch **Dark**, **System**, **Light** with the Settings window and 1 sheet open. Every window changes at once.
- A catalog check fails the build when a `vi` entry is missing, `new`, or `stale`.
- A Vietnamese run of all screens has no cut text at the minimum window size (1000 × 680).
- `swift test` and the app tests pass after each phase.
- A new contributor adds a test language (for example `fr` with 3 strings) by following `CONTRIBUTING.md` only.
- VoiceOver reads a label for each button that has only an icon.

## 9. Work left to the builder

- Exact colors, sizes, and fonts, read from the PNG files.
- File layout of the new views, as long as the layers stay.
- The name and API of the new Phase 3 types.
- The way to test a SwiftUI view (snapshot test, preview, or manual list).
- How the pseudo-language and CI checks run.

## 10. Known limits

- The catalog tests check only the keys that are already in the catalog. They cannot find a text in the code that the catalog lacks.
- Run `python3 -I scripts/sync-string-catalog.py --check` before each commit. It finds the code texts that the catalog lacks.
- The build has no phase that fails on a missing string.
