---
id: picnest-macos-app-design
title: Picnest macOS App Design
type: spec
status: active
tags: [picnest, macos, swiftui, coreml, design]
links:
  - "[[dictionary]]"
  - "[[2026-10-21-macos-app-plan]]"
  - "[[BUILD]]"
  - "[[2026-10-23-picnest-split-plan]]"
---

# Picnest macOS App Design

## 1. Intent

The user and the user's wife have large folders of photos with ID names (for example `z7913505267117_a3f.jpg`, `1718202933221.jpg`). The folders are messy. They want to sort the photos into content categories without the terminal.

The [Python CLI](https://github.com/megabuild-dev/classifyimages/blob/main/docs/specs/2026-10-14-image-classifier-design.md) does the sorting, but it has 3 problems for these users:

- The user must edit `categories.yaml` by hand and write English prompts.
- The review page `review.html` is read-only. The user cannot fix a wrong category in it.
- The output always has date sub-folders.

The app replaces the CLI workflow with 1 native macOS window. The user sees each photo, fixes wrong categories, and then sorts all photos in 1 batch.

Terms are defined in [[dictionary]]. Section 13 adds the new app terms.

### 1.1 Users

- The user and the user's wife. Both use their own Macs with Apple silicon.
- The app is for macOS only (user decision). It is not a universal iPhone or iPad app.
- The wife must never need the terminal, a YAML file, or an English prompt.
- The interface language is English only.

### 1.2 Requirements from the user

| # | Requirement |
|---|-------------|
| R1 | A native macOS app. The look follows the reference screenshot (section 6.1). |
| R2 | The app sorts photos into category folders. |
| R3 | Date sub-folders are optional. If the user does not tick the option, the app makes no date folder. |
| R4 | The user can change the category of any photo before the sort. |
| R5 | The user can act on "Not sure" photos in batch: accept all, accept 1 group, or select and move. |
| R6 | The Sort sheet also has an option to accept the best guess for all "Not sure" photos. |
| R7 | 1 batch operation copies or moves all photos to their folders. |
| R8 | Bigger thumbnails and a small header on the review screens. |
| R9 | Swift rewrite with Core ML. The app does not use the Python code. |
| R10 | The user can remove folders from the recent folder list (feedback 2026-10-22). |
| R11 | "Rename files" gives the date, the category, and a number in each name (feedback 2026-10-22). |
| R12 | The app finds exact copies and similar photos. The user keeps 1 and moves the others to the Trash (feedback 2026-10-22). |
| R13 | When many photos are "Not sure", the app suggests new categories. The user accepts, renames, or skips each one (feedback 2026-10-22). |
| R14 | The user can move selected photos to the Trash from a right-click menu (feedback 2026-10-22). |
| R15 | The Return key opens the selected photo (feedback 2026-10-22). |
| R16 | If a session has no categories, Rescan proposes categories again (feedback 2026-10-23). |
| R17 | **Start Over…** scans the folder again and proposes new categories (feedback 2026-10-23). |
| R18 | After a scan, the app opens the Suggest Categories sheet when many photos are "Not sure" (feedback 2026-10-23). |
| R19 | The app gives each proposed and suggested category a meaningful name for any folder. The user does not select a list. "Group <n>" is a last resort (feedback 2026-10-23). |
| R20 | The user can share a photo from the right-click menu (for example to Zalo) (feedback 2026-10-24). |

### 1.3 Goals

- The wife can sort a folder of 2,000 photos without help.
- The app never loses a file.
- A fix by the user is never changed by the app.

### 1.4 Non-goals (version 1)

- App Store release.
- Content classification of videos.
- Duplicate detection of videos.
- Photos library (Photos.app) import. The app works only on Finder folders.
- Interface languages other than English.
- iOS or iPadOS versions.

### 1.5 Anti-goals

These results make the app a failure, even if it works:

- The app deletes or overwrites a file that the user did not tell it to move.
- The app changes a category that the user picked by hand.
- The user must open a text file or a terminal to finish a sort.
- The app looks like a web page in a window, not a Mac app.
- The app sends a photo or a photo embedding to a network service.

### 1.6 Success criteria

- The app processes a test folder of 2,000 photos without a crash.
- On an M1 Mac, the first scan of 2,000 photos takes at most 5 minutes. A second scan of the same folder takes at most 30 seconds.
- On a sample check of 50 photos, the user agrees with at least 85% of the automatic categories. This is a target, not a gate (section 11).
- Copy, then Undo, gives a source folder and an output folder that are the same as before. Move, then Undo, gives the same result.

## 2. User flow

1. The user opens the app. The app shows the Welcome screen.
2. The user drops a folder on the window, or clicks **Choose Folder…**.
3. The app scans the folder. It shows the Scan screen with a progress bar.
4. The app proposes categories and assigns each photo. It shows the Review screen.
5. The user renames, merges, deletes, or adds categories in the sidebar.
6. The user fixes wrong photos and handles "Not sure" photos.
7. The user clicks **Sort Photos…**. The app shows the Sort sheet.
8. The user selects the options and clicks **Sort**. The app copies or moves the files.
9. The toolbar shows **Undo Last Sort** until the user starts a new sort.

The user can quit at any step before the sort. When the user opens the same folder again, the app continues from the saved session (section 9).

Each sort is one-off (user decision). The user does not sort the same folder again to add new photos. After a sort, the session closes (section 9.1).

## 3. Screens

The mockups are in `docs/specs/assets/2026-10-21-macos-app/`. Open them in a browser.

| File | Content |
|------|---------|
| `native-v2.html` | First native look. Use it only for the sidebar style and the Sort sheet frame. Its large header is replaced by v3. |
| `notsure-v3.html` | Approved Review screen: compact toolbar, big thumbnails, "Not sure" view, category view. |
| `sheet-v4.html` | Approved Sort sheet. |

The mockups are wireframes in HTML. Use native SwiftUI controls, not copies of the HTML.

### 3.1 Welcome screen

- A drop zone with the text "Drop a folder of photos here" and a **Choose Folder…** button.
- A list of the 5 most recent folders, with the photo count for each.
- Right-click a recent folder: **Remove from Recent**. A **Clear Recent Folders** button is at the end of the list. These actions remove only the list entries. The app keeps the session of each folder. If the user opens the folder again, the review continues (section 9). The app does not ask for confirmation.
- The text "Everything runs on this Mac. No photos leave your computer."

### 3.2 Scan screen

- A progress bar with the count (for example `1,240 / 2,413`) and the estimated time left.
- A **Cancel** button. Cancel keeps the embeddings that the app already calculated.
- On the first start only, the app loads the Core ML model. It shows "Preparing the model…" during this step.

### 3.3 Review screen

The window has a sidebar and a main area (`NavigationSplitView`).

**Sidebar** (from top to bottom):

| Section | Items |
|---------|-------|
| Review | All photos, Not sure, Changed by you. Each item shows a count. |
| Categories | 1 item for each category: an emoji icon, the name, the count. Then **New Category…**. |
| Tools | Duplicates, with the count of photos the app can move to the Trash (section 3.6). |
| Other | Don't move, Videos, Unreadable. |

- The user can drop photos on a category item. The item shows a highlight during the drag.
- Right-click on a category: Rename, Change Icon, Merge Into…, Delete.
- Delete moves all photos of that category to "Not sure", also the manual picks. They stay in "Not sure" until the user acts on them, even if a new score is high. The app asks for confirmation first. (Builder decision, made during the spec review.)
- Merge moves all photos into the target category. Photos the user picked by hand keep the "Changed by you" status.
- Keys `1` to `9` match the first 9 categories in the sidebar order. The user can drag categories to change the order.

**Toolbar** (1 row, no large header):

- The title of the selected sidebar item and its count as a chip.
- The source folder path, in a small monospaced font.
- A thumbnail size slider.
- **Rescan**.
- In the "Not sure" view only: **Accept All Best Guesses**.
- **Sort Photos…** in the accent color.

**Photo grid:**

- 3 columns at the default slider position. The slider sets 2 to 8 columns.
- Each tile shows the photo, the file name, and a second line on top of the image.
- In a category view, the second line is the date. In the "Not sure" view, it is the second guess (for example "or Documents 38%").
- A badge at the top left shows the score as a percentage. The badge is green if the photo is not uncertain, and amber if it is uncertain.
- A photo that the user picked by hand shows a green "✓ You" badge, not a score.
- Sort order menu: Lowest confidence (default), Date, Name.
- Click selects 1 photo. ⌘-click and ⇧-click add to the selection. ⌘A selects all photos in the view.
- Space and Return open the selected photo in Quick Look.
- Double-click opens the photo in Quick Look.
- Right-click a photo: if the photo is not selected, the app selects only that photo first. The menu has **Quick Look**, **Open**, **Show in Finder**, **Share…**, **Move to…**, **Accept Best Guess** (only for "Not sure" photos), **Don't Move**, and **Move to Trash**. **Open** opens the photo in its default app (for example Preview). **Share…** opens the macOS share sheet for the selected photos, with the apps and share extensions that accept them (for example Zalo, Messages, Mail, and AirDrop).
- **Move to Trash** (also ⌘⌫) moves the selected photos to the macOS Trash (section 7.4). The app does not ask for confirmation. ⌘Z puts the photos back.

**Selection bar** (shows at the bottom when 1 or more photos are selected):

- The count of selected photos.
- **Accept Best Guess** (only if at least 1 selected photo is uncertain).
- **Move to…**: a menu of all categories with their number keys, and **New Category…**.
- **Don't Move**.
- **Move to Trash**.
- A hint: "or drag to a category · 1–9".

**Start Over…** (File menu, ⇧⌘R):

- The app asks first. Title: "Start over?". Text: "The app scans the folder again and proposes new categories. Your categories and picks are lost." If the folder was sorted, the text adds "The last sort can no longer be undone." Buttons: **Start Over** and **Cancel**.
- The app deletes the session file and archives the journal of the last sort. It keeps the embedding cache and the hash cache, so the scan is faster. It does not change photo files.
- Then the app runs a first scan (section 4.3).
- The command is off while a sort, an undo of a sort, or a Trash move runs. If the last sort did not finish, the app shows the message of section 7.3 rule 6 and changes nothing.

**Undo:** ⌘Z reverses the last change of category, accept, merge, delete, Move to Trash, accepted suggestion, or duplicate clean-up. ⇧⌘Z does it again. This undo is for review changes only. It is not the same as **Undo Last Sort**.

### 3.4 "Not sure" view

- An amber notice line: "The app is not confident about these photos. They are grouped by best guess. Accept a group, or select photos and move them."
- The photos are grouped by best category. Each group header shows "Best guess: <category>", the count, **Select All**, and **Accept <N>**.
- Groups are sorted by size, largest first.
- When the user accepts a photo, it leaves this view. It goes to its best category with the "Changed by you" status.
- The toolbar has **Suggest Categories…** when the view has at least 7 photos. It opens the Suggest Categories sheet (section 3.7).

### 3.6 Duplicates view

The user opens this view from the **Duplicates** item in the sidebar. The view finds 2 kinds of groups (section 4.9):

- **Exact copies**: files with the same content.
- **Similar photos**: photos that look almost the same, for example 3 shots of the same moment.

Layout:

- A notice line: "Check each group. The app moves the photos that are not marked Keep to the Trash."
- A segmented control: **Exact copies** (default) and **Similar photos**. Each segment shows its group count.
- 1 card for each group. The card shows the photos side by side, as in the reference screenshot (section 6.1). Each tile shows the file name, the pixel size, and the file size.
- The app marks the best photo of each group with a **Keep** badge (section 4.9). The user clicks a tile to mark or unmark Keep. A group always has at least 1 Keep photo. In similar groups, the user can keep more than 1 photo.
- Each card has **Move <N> to Trash** and **Not Duplicates**. **Not Duplicates** hides the group. The session stores this choice.
- The toolbar has **Clean Up All** with the total count. It asks for confirmation: "Move <N> photos to the Trash? You can put them back with Undo or from the Trash in Finder."
- Space, Return, and double-click open Quick Look for a tile.
- When no group is left, the view shows "No duplicates found."

The app finds duplicates when the user opens the view for the first time in a session. It shows a progress bar during this step. It finds them again after a rescan.

### 3.7 Suggest Categories sheet

- The sheet opens from **Suggest Categories…** in the "Not sure" view or in the Sort sheet.
- The sheet also opens by itself when the Review screen opens after a first scan or a rescan. It opens only if at least 20 photos are "Not sure" and they are at least 10% of the photos. The Sort sheet hint uses the same rule (section 3.5). If the user closes it, it does not open again until the next scan.
- While it works, the sheet shows "Looking for groups…" and a progress indicator.
- Then it shows 1 row for each suggestion: a check box (on by default), the emoji, the name in an editable text field, the photo count, and 4 thumbnails.
- The user can change the name and the emoji, and clear the check box to skip a suggestion.
- **Add <N> Categories** creates the checked categories at the end of the sidebar. It moves their photos into them as manual picks (section 4.7). The whole action is 1 review undo step.
- If the app finds no group, the sheet shows "No new groups found. Move the photos by hand or make a category with New Category…".

### 3.5 Sort sheet

The sheet opens over the Review screen.

| Control | Default | Notes |
|---------|---------|-------|
| Title | — | "Sort <N> photos into <M> folders". |
| Destination | `<source folder> - sorted`, next to the source folder | **Change…** opens a folder picker. The destination must be outside the source folder. |
| Copy / Move | Copy | Move text: "Each original is deleted after its copy is checked." |
| Make date sub-folders | Off | Format: `YYYY-MM`, the same as the CLI. |
| Rename files to date + category + number | Off | Format in section 7.2. |
| "Not sure" photos | Accept best guess | 3 choices: Accept best guess, Put in a "Not sure" folder, Leave in the source folder. Show this group only if at least 1 photo is still "Not sure". |
| Preview | — | A folder tree with the first 3 folders and their counts. It changes when an option changes. |
| Buttons | — | **Cancel**, **Sort**. |

If at least 20 photos are still "Not sure", and they are at least 10% of the photos, the sheet shows a hint: "<N> photos are not sure." with a **Suggest Categories…** button. The button closes the Sort sheet, shows the "Not sure" view, and opens the Suggest Categories sheet.

If the user selects Move, the **Sort** button text changes to **Move <N> Photos**. The app asks for confirmation 1 more time.

During the sort, the sheet shows a progress bar and a **Stop** button. Stop finishes the current file, writes the journal, and stops. The user can then click **Undo Last Sort**.

After the sort, the sheet shows a summary and 2 buttons: **Show in Finder** and **Done**.

## 4. Classification rules

### 4.1 Model

- Use Apple MobileCLIP in Core ML format. Use the image encoder and the text encoder.
- Bundle the model in the app. The app needs no network access.
- The builder selects the model size (S0, S1, S2, or B) in phase 0 (section 11). The choice depends on accuracy and speed.
- If no MobileCLIP size reaches the accuracy target, convert OpenCLIP `ViT-B-32` (`laion2b_s34b_b79k`) to Core ML with `coremltools`. This is the CLI model.

### 4.2 Embeddings

- 1 L2-normalized vector for each photo and each text prompt.
- The cache key is the path, the size, and the modification time. This is the same rule as the CLI.
- Calculate embeddings in batches on a background task. The interface must stay responsive.

### 4.3 Proposed categories (first scan)

This step replaces CLI `discover`. The rules are the same as CLI section 4.1, with these changes:

- Use k-means. If the folder has 42 photos or more, test k from 6 to 14. If it has 7 to 41 photos, test k from 2 to n ÷ 7 (minimum 2), where n is the photo count. If it has fewer than 7 photos, make 1 category. Select the k with the best silhouette score. Use Accelerate for the math.
- Name each cluster with the best match from a built-in candidate list.
- The app ships 1 built-in candidate list, **All topics**. It holds the Everyday entries, the Art studio entries (the CLI `CANDIDATES` list), and at least 200 more common photo topics. No 2 entries have the same display name (case-insensitive), and clear synonyms are merged into 1 entry. A merged or shortened entry keeps the old name as an alias, so a category of an old session counts as the same entry.
- Each candidate has a display name, an emoji icon, and 1 or more English prompts. The user never sees the prompts.
- The user does not select a list. The first scan, Rescan, **Start Over…**, and suggestions all use **All topics** (feedback 2026-10-23).
- If 2 or more clusters get the same candidate, merge them into 1 category.

### 4.4 Category score

Each category has 2 kinds of reference:

- **Prompts**: from the candidate list. A category that the user makes with **New Category…** gets 1 prompt: "a photo of <name>".
- **Examples**: the embeddings of photos that the user put in this category by hand.

Calculate the score of a photo for a category as follows:

1. Prompt score = the highest cosine similarity between the photo and the category prompts.
2. Example score = the mean of the 3 highest cosine similarities between the photo and the category examples. If the category has fewer than 3 examples, use the mean of all of them. If it has no example, there is no example score.
3. Category score = the higher of the 2 scores, after the builder puts both on the same scale (section 4.6).

The builder can change this formula in phase 0 if the test data shows a better rule. Record the final rule in this spec.

### 4.5 Uncertain rule

- A photo is uncertain if its best score is less than `min_score`, or if (best score − second score) is less than `min_margin`.
- The builder sets the default values in phase 0 for the selected model. The CLI values (0.22 and 0.02) are for `ViT-B-32` and do not apply directly.
- Version 1 has no setting in the interface for these values.

### 4.6 Score scale

The percentage in the badge must be easy to understand. Use a softmax over all category scores with a fixed temperature. The builder selects the temperature in phase 0. Show the result as a whole percentage.

### 4.7 Manual picks

- A manual pick is a photo that the user put in a category by hand, or accepted from "Not sure".
- The app never changes a manual pick. Rescan, new examples, and category changes do not change it.
- Only these user actions change a manual pick: a new move by the user, Merge, Delete of its category, review undo (⌘Z), and removal of its file (section 5.1).
- After each manual pick, the app calculates the scores again for all photos that are not manual picks. Do this on a background task. Show the new counts within 2 seconds for 5,000 photos.

### 4.8 Suggested categories

This step uses the same method as section 4.3, but only on the "Not sure" photos.

1. Take the photos that are "Not sure" (`isNotSure`). If there are fewer than 7, the app suggests nothing.
2. Make clusters with the k range of section 4.3, for this photo count.
3. Drop each cluster with fewer than 3 photos.
4. Name each cluster with the best candidate from **All topics**, also for an old session that saved another list. Do not use a candidate whose display name or alias is the same as an existing category name (case-insensitive). Use the next best candidate. If 2 clusters get the same candidate, merge them.
5. Use the best candidate that is left, also if its score is less than `minScore`. The user can rename it in the sheet. Only if no candidate is left, name the cluster "Group 1", "Group 2", and so on, with the emoji 📁.
6. Sort the suggestions by size, largest first.

A new category from a suggestion gets the prompts of its candidate. A "Group <n>" category gets the prompt "a photo of <name>" after the user names it. Its photos become examples (section 4.4), so the name does not change the scores much.

### 4.9 Duplicate rules

- **Exact copies**: 2 or more images with the same file size and the same SHA-256 hash of the file content. The app calculates the hash only for files whose size is not unique. The app caches the hash in the session folder (`hashes.json`), with the key of section 4.2.
- **Similar photos**: images whose embeddings have a cosine similarity of at least `duplicateSimilarity`. Default: 0.95 (provisional; phase 0 tunes it). Join similar pairs into groups. Then keep in each group only the photos that are similar to its Keep photo. Make new groups from the other photos with the same rule. The app does not show an exact-copy group again as a similar group.
- Use 1 matrix multiply for each block of 1,000 photos, so 10,000 photos take less than 10 seconds.
- Videos and unreadable files are not in duplicate groups.
- **Best photo** (the default Keep): the most pixels, then the largest file size, then the oldest date, then the shortest relative path.
- The app never moves a photo to the Trash without a user action.

## 5. Scan rules

These rules are the same as CLI sections 3.2, 3.3, and 3.4, unless this section changes them.

- Supported photo types: `.jpg`, `.jpeg`, `.png`, `.heic`, `.heif`, `.webp`, `.gif` (first frame), `.tiff`.
- Read images, EXIF data, and thumbnails with ImageIO.
- Skip rules: the CLI skip rules. Also skip the output folder, the app session data, and symbolic links to files or folders.
- Videos (`.mov`, `.mp4`, `.m4v`) go to the Videos sidebar item. The app does not classify them.
- If the app cannot open an image, it goes to the Unreadable sidebar item.
- Scan subfolders. The relative path of each photo stays in the session data.

### 5.1 Rescan

- Rescan finds new, changed, and removed files in the source folder.
- It calculates embeddings for new and changed files only. It scores them against the current categories.
- Rescan never runs clustering again, with 1 exception: if the session has no categories, Rescan proposes categories as a first scan does (section 4.3). "Don't move" photos keep their state.
- Rescan never changes category names, icons, order, merges, or manual picks.
- If the file of a manual pick is removed, the app removes the photo from the session. Its example is removed too.
- **Start Over…** (section 3.3) proposes categories again from the start.

(Builder decision, made during the spec review.)

### 5.2 Date rules

The app uses the first date that it finds, in this order:

1. EXIF `DateTimeOriginal`.
2. A 13-digit millisecond timestamp at the start of the file name, if the year is from 2000 to 2100.
3. The file modification time.

Zalo names (`z<number>_...`) do not contain a date. The app does not read a date from them. The tile shows "no date" if the date comes from the modification time only. The date is still used for date folders.

## 6. Look and feel

### 6.1 Reference

The user gave a screenshot of a CleanMyMac-style "Similar Photos" screen as the target look. Its main features:

- A translucent sidebar with small uppercase section labels and icons in rounded squares.
- The selected sidebar item has a light accent background and a thin accent bar on the left.
- Rounded cards with thin borders, chips with a soft background, and a pill-shaped accent button.

The user then asked for a smaller header. The Review screen uses the compact toolbar of `notsure-v3.html`, not the large header of the reference.

### 6.2 Rules

- Use SwiftUI system controls and SF Symbols. Use emoji only for category icons.
- Accent color: rose `#C8557A` (placeholder). Define it 1 time as an asset color, so it is easy to change.
- Support light mode and dark mode.
- Minimum window size: 1000 × 680 points.

## 7. Output rules

### 7.1 Layout

```
<destination>/
  <category folder>/
    [YYYY-MM/]                 only if "Make date sub-folders" is on
      <file name>
  Not sure/                    only if that choice is selected
  Videos/
  Unreadable/
```

- The destination must be outside the source folder. The app refuses the source folder and each folder in it. Reason: the scan cannot skip a destination that it does not know, so a rescan would read the sorted files as new photos.
- No folder that gets files can be the source folder or a folder in it. Example: the source is `~/Pictures/Food`, the destination is `~/Pictures`, and a category has the name "Food". The app refuses this plan.
- The category folder name is the display name of the category (for example `Kids' artwork`). Replace `/` and `:` with `-`.
- Photos marked "Don't move" stay in the source folder.
- Photos under "Leave in the source folder" stay in the source folder.
- The app writes no hidden file into the destination folder.

### 7.2 File names

- Default: keep the original file name.
- If "Rename files to date + category + number" is on: `YYYY-MM-DD_<folder name>_NNN.<ext>` (for example `2024-05-12_Kids' artwork_001.jpg`). `<folder name>` is the name of the folder that gets the file: the category folder name (section 7.1), `Not sure`, or `Videos`. `NNN` is a 3-digit counter for each date and destination folder. It starts at `001`. Lowercase the extension. `.jpeg` becomes `.jpg`. Unreadable files keep their original names.
- Name collision: add ` 2`, ` 3`, and so on before the extension, until the name is free. Never overwrite a file.

### 7.3 Sort operation

These rules are the same as CLI sections 4.4 and 4.5:

1. Before the first file operation, make sure that each source file has the same size and modification time as at the scan. If 1 file is different, stop and ask the user to click **Rescan**.
2. Make sure that no destination file exists. Section 7.2 changes the names to prevent collisions, so this check finds only files that appeared during the sort.
3. For each photo: make the folder, copy the file with its metadata, and write 1 journal line.
4. Move mode: after the copy, compare the size of the copy with the size of the source. If they are equal, delete the source. If they are not equal, stop and keep the source.
5. Write a `done` journal line at the end.
6. If the journal of the last sort has no `done` line, the app does not start a new sort. It tells the user to click **Undo Last Sort** first.

**Undo Last Sort** reverses the journal from the last line to the first. This is the same as CLI `undo`. Then it deletes the empty folders that the sort made.

Move mode deletes the source file with `FileManager.removeItem`, not to the Trash. Reason: the copy is checked first, and Undo copies the file back. The builder can use the Trash instead if the user asks for it.

### 7.4 Move to Trash

- The app moves a photo to the Trash with `FileManager.trashItem(at:resultingItemURL:)`. The file goes to the user's Trash, and Finder can put it back.
- The session records the photo as trashed, with the path of the file in the Trash (`trashPath`). A trashed photo leaves all views, counts, duplicate groups, and sorts. It is not an example any more.
- Review undo (⌘Z) moves the file back from the Trash to its original path. If the Trash file is gone (the user emptied the Trash), or if a file exists at the original path, undo does not move it. The app shows "The photo could not be put back: <reason>." and keeps the photo trashed.
- A rescan removes trashed photos from the session if their file is not at the original path. A photo that the user put back with Finder comes back as a new photo.
- Move to Trash is not part of the sort journal. **Undo Last Sort** does not change trashed photos.
- These actions move files to or from the Trash: Move to Trash, a duplicate clean-up, and a Trash undo or redo. While one runs, the app turns off **Sort Photos…**, **Rescan**, **Done**, and **Undo Last Sort**. Sort, Rescan, and Done also wait until the moves end.

## 8. Permissions and distribution

- Do not use App Sandbox. The app is not for the App Store. Without the sandbox, the app can make the default destination next to the source folder. (Builder decision, made during the spec review.)
- Turn on the hardened runtime. Xcode turns it off again for an ad-hoc signature ("Disabling hardened runtime with ad-hoc codesigning"), so it is not active in a release build today. The app keeps the `com.apple.security.cs.disable-library-validation` entitlement for a build where the runtime is active, because no Developer ID signs `Sparkle.framework`.
- macOS asks the user one time for access to Desktop, Documents, or Downloads. The app must continue correctly after the user approves.
- Save a bookmark for each recent folder, so the app can find the folder after a rename or a move.
- The project is open source under the MIT license (user decision, 2026-10-23). There is no App Store release.
- The project signs with "Sign to Run Locally". A builder does not need a paid Apple Developer account.
- `scripts/make-dmg.sh` makes a DMG for the GitHub release page. Without a Developer ID, the DMG has an ad hoc signature, and users click Open Anyway one time. With a Developer ID and a notary profile, the script signs, notarizes, and staples the DMG.
- The app updates itself with the Swift package Sparkle 2 (user decision, 2026-10-24). The user opens **Picnest > Check for Updates…**, or the app checks 1 time a day and asks before the install. Sparkle replaces the app in `/Applications` and starts it again. An update keeps the sessions in Application Support.
- `scripts/make-appcast.sh` signs each update archive and writes `docs/appcast.xml`, the feed that Sparkle reads. GitHub Pages serves the feed, and the GitHub release with the tag `updates` holds the archives. The first install still needs Open Anyway; an update does not, because Sparkle does not quarantine its download.
- Each archive carries an EdDSA signature. The public key is `SUPublicEDKey` in the Info.plist, and the private key is in the login Keychain. Save the private key outside the Mac: with no Developer ID, Sparkle cannot replace a lost key, and each user must then install the app again by hand.
- The app touches the network only for the update check. The README states this, and the "Private" feature line must stay true.
- Write a short guide: install Xcode, open the project, select the Mac as the run target, and click Run. The guide also tells how to copy the built app to `/Applications`, and how to make and publish a DMG.
- If a free-team signature stops the app from opening, build it again on that Mac.

## 9. Session data

- Save 1 session for each source folder in `~/Library/Application Support/<bundle id>/Sessions/<hash of source path>/`.
- The session holds the categories, the manual picks, the embedding cache, the last scan result, and the journals.
- Use SwiftData or JSON files. JSON is easier to check by hand. The builder selects 1 and records the choice.
- The app saves after each change. If the app quits during a scan, the next start continues the scan from the cache.
- If the user moves or renames the source folder, the app asks the user to find it again.

### 9.1 After a sort

- When the user clicks **Done**, the session closes. The app goes back to the Welcome screen.
- The app keeps the journal of the last sort. The recent folder list shows "Sorted <date>" and an **Undo Last Sort** button for that folder.
- **Undo Last Sort** stays available until the user starts a new session for that folder.
- If the user opens a sorted folder again, the app asks: "This folder was sorted on <date>." The dialog text is "If you start a new sort, the last sort can no longer be undone." It has 3 buttons: **Undo Last Sort**, **Start a New Sort**, and **Cancel**. **Undo Last Sort** reverses the sort and opens the review. **Start a New Sort** deletes the old session and starts from the scan. The app hides **Undo Last Sort** if the journal holds old paths (the folder was moved).
- This dialog lets the user undo a sort after the folder was removed from the recent list.
- The app does not track which photos are already sorted. Version 1 has no "add new photos to an old sort" mode.

## 10. Architecture

The layers follow the user rules in `~/.claude/CLAUDE.md`, adapted for Swift. Each layer calls only the layer below it.

```
Views (SwiftUI)                 Show state, send user actions. No logic.
  ↕
View models (@Observable)       State for 1 screen. Call services.
  ↕
Services                        Classification, review changes, sort, undo.
  ↕
Repositories                    Files, images, embeddings, session, journal.
  ↕
API                             Core ML, ImageIO, FileManager, QuickLook.
```

- Put the services, repositories, and domain types in a local Swift package (`PicnestCore`). The app target holds the views and view models only.
- Define the domain types in `PicnestCore/Domain/` before other code.
- Services receive an `Embedder` protocol with 2 methods: `embedImages(_ urls:) async throws -> [Vector]` and `embedTexts(_ texts:) async throws -> [Vector]`. Tests use a fake embedder.
- Views never call a service or a repository directly.

### 10.1 Suggested parts

| Part | Layer | Job |
|------|-------|-----|
| `ScanService` | Service | Scan, embeddings, first proposed categories. |
| `ClassifyService` | Service | Scores, uncertain rule, calculation after a change. |
| `ReviewService` | Service | Manual picks, accept, merge, delete, review undo stack. |
| `SortService` | Service | Destination paths, sort, undo. |
| `MediaRepository` | Repository | Folder scan, skip rules, dates. |
| `ImageRepository` | Repository | Thumbnails, EXIF, image open. |
| `EmbeddingRepository` | Repository | Core ML model and embedding cache. |
| `SessionRepository` | Repository | Read and write session data. |
| `JournalRepository` | Repository | Read and write journals. |
| `BookmarkRepository` | Repository | Bookmarks for recent folders. |
| `DuplicateService` | Service | Exact and similar groups, best photo, clean-up. |
| `SuggestionService` | Service | Clusters of "Not sure" photos and their names (section 4.8). |
| `TrashService` | Service | Move to Trash and put back, with review undo. |
| `HashRepository` | Repository | SHA-256 of file content, with a cache. |

### 10.2 Domain types

Port these CLI types: `MediaKind`, `MediaFile`, `Category`, `Settings`, `Assignment`, `PlanEntry`, `JournalEntry`, `ScanResult`.

Add these types:

- `Category` gets `id`, `displayName`, `emoji`, `prompts`, `exampleIDs`, `order`.
- `PhotoState`: `.auto(Assignment)`, `.manual(categoryID)`, `.heldNotSure(Assignment)`, `.dontMove`, `.unreadable`. `.heldNotSure` is for the photos of a deleted category. It shows in "Not sure" whatever its score is.
- `SortOptions`: `destination`, `mode` (copy or move), `dateFolders`, `rename`, `notSureChoice`.
- `ReviewChange`: 1 entry of the review undo stack. It also records the files that an action moved to the Trash.
- `TrashedPhoto`: `mediaID`, `trashPath` (the path of the file in the Trash, a string), `time`. The session keeps a list of them.
- `DuplicateGroup`: `kind` (exact or similar), `ids`, `keepIDs`. The session keeps the keys of groups marked **Not Duplicates**.
- `CategorySuggestion`: `name`, `emoji`, `prompts`, `ids`.

## 11. Delivery phases

The implementation plan breaks these phases into tasks. Each phase ends with a working build.

| Phase | Content | Exit check |
|-------|---------|------------|
| 0. Model test | The user gives the path of the Zalo photo folder (user decision). A command-line Swift tool selects 50 random photos from it and writes a labels file (CSV) and a page with thumbnails. The user or the user's wife writes the right category for each photo, from the Everyday list. Then the tool embeds the 50 photos with each MobileCLIP size and compares the results with the labels and with the CLI. Select the model, the score rule, `min_score`, `min_margin`, and the temperature. | Record the agreement of each model in this spec. Target: 85%. If no model reaches 85%, use the best model and continue to phase 1 (user decision). More photos will be "Not sure". |
| 1. Core package | Domain types, repositories, scan, dates, embeddings with cache. | Unit tests pass. A test command prints the scan summary for a folder. |
| 2. Classify | Proposed categories, scores, uncertain rule, manual picks, examples. | Unit tests pass with the fake embedder. |
| 3. Sort and undo | Destination paths, copy, move, journal, undo. | Copy + undo and move + undo tests give the original state. |
| 4. App shell | Welcome, Scan, Review screens, sidebar, grid, Quick Look. | The user can open a folder and see the categories. |
| 5. Review actions | Drag, keys, Move to…, Accept, "Not sure" view, category edits, review undo. | The user can fix and accept photos. Changes stay after the app restarts. |
| 6. Sort sheet | Options, preview, progress, summary, Undo Last Sort. | Full flow on a copy of a real folder of 500 photos. |
| 7. Small feedback items | Remove from Recent, Clear Recent Folders, reopen dialog with Undo Last Sort, new rename format, Return opens Quick Look, photo right-click menu. | Tests pass. |
| 8. Move to Trash | Trash and put back, review undo, rescan rules. | Trash + undo test gives the original folder. |
| 9. Suggested categories | Suggestion rules, Suggest Categories sheet, Sort sheet hint. | Tests pass with the fake embedder. |
| 10. Duplicates | Hashes, similar groups, best photo, Duplicates view, clean-up. | Tests pass. Clean-up + undo gives the original folder. |
| 11. Start over and suggestions after a scan | Rescan of a session with no categories, **Start Over…**, Suggest Categories sheet after a scan. | Tests pass. |
| 12. Automatic names | The **All topics** list, names without "Group <n>", no list menu on the Welcome screen. | Tests pass. |

## 12. Risks

| # | Risk | Effect | Action |
|---|------|--------|--------|
| 1 | MobileCLIP is less accurate than `ViT-B-32` on these photos. | More wrong categories. More work for the user. | Phase 0 measures this before any app code. Fallback: convert `ViT-B-32` to Core ML. |
| 2 | A bug in Move mode loses files. | Lost photos. | Copy is the default. Size check before delete. Journal and undo. Check for changed files before the sort. Tests for move + undo. |
| 3 | Large folders (10,000+ photos). | Slow scan, high memory use, slow grid. | Embedding cache. Batched embeddings. `LazyVGrid`. Thumbnails load only when visible, from a cache of limited size. |
| 4 | macOS privacy prompts block folder access. | The app cannot read or write files in Desktop, Documents, or Downloads. | No App Sandbox. Handle the denied case with a clear message and a button that opens System Settings. |
| 5 | Swift rewrite takes longer than planned. | Late app. | Small phases. Phase 0 and phase 1 have no interface. The CLI spec is the reference for all file rules. |
| 6 | Wrong dates for files without EXIF. | Photos in the wrong date folder. | Date folders are off by default. Tiles show "no date" for modification-time dates. |
| 7 | The model makes the app large. | Download size of 100 MB to 600 MB. | Accept it for version 1. The phase 0 model choice includes size. |
| 8 | No notarization (no paid account). | The first install needs Open Anyway. A free-team signature can stop working. | Build on each Mac with Xcode. Section 8 guide. An update replaces the app in place, and Sparkle does not quarantine its download, so only the first install prompts. |
| 9 | Similar-photo groups join photos that the user sees as different. | The user could trash a photo by mistake. | Only a user action trashes photos. Keep is pre-marked, the user checks each group, Clean Up All asks for confirmation, and undo and the Trash can put photos back. |
| 10 | Hashing a large folder takes time. | Slow Duplicates view. | Hash only files whose size is not unique. Cache the hashes. |
| 11 | The EdDSA update key is lost, and the project has no Developer ID. | Sparkle cannot replace the key. Every user must install the app again by hand. | Save the private key outside the Mac on the day the project makes it. Section 8 and BUILD.md. |

## 13. New terms

These terms are also in [[dictionary]]:

| Term | Meaning |
|------|---------|
| Manual pick | A photo that the user put in a category by hand, or accepted from "Not sure". The app never changes it. |
| Example | The embedding of a manual pick. The app uses it to score other photos for the same category. |
| Not sure | The app name for an uncertain photo. |
| Session | The saved state of the app for 1 source folder. |
| Sort | The app name for CLI `apply`. |
| Review undo | ⌘Z in the Review screen. It reverses 1 review change. It changes files only to put back photos from the Trash. |
| Duplicate group | 2 or more photos that are exact copies or look almost the same. |
| Keep photo | The photo of a duplicate group that the app does not move to the Trash. |
| Suggested category | A new category that the app proposes for a group of "Not sure" photos. |

## 14. Open questions and builder decisions

**User decisions from the spec review:**

- Each sort is one-off (section 9.1).
- No paid Apple Developer account. Build in Xcode on each Mac (section 8).
- Phase 0 uses 50 photos from the Zalo folder (section 11).
- If no model reaches 85%, continue with the best model (section 11).

**Decisions for the builder** (record each one in this spec). The builder already decided: no App Sandbox (section 8), Rescan rules (section 5.1), Delete holds photos in "Not sure" (section 3.3).

- MobileCLIP size, score rule, `min_score`, `min_margin`, and softmax temperature (phase 0).
- SwiftData or JSON for the session data.
- The Everyday candidate list.
- The minimum macOS version. Default: macOS 15.

**Builder decisions (recorded 2026-10-21):**

- Session data: JSON files. Each session folder holds `session.json`, the embedding cache, and the journals (`journal.jsonl`). Reason: a person can read and check JSON in a text editor (section 9).
- Everyday list: `candidates-everyday.json` in the `PicnestCore` resources, with 51 entries. The Art studio list is `candidates-art.json`. Since phase 12 the app uses `candidates-all.json` (**All topics**). ModelBench still uses the 2 old lists.
- Minimum macOS version: macOS 15.0.
- Bundle ID: `dev.megabuild.picnest`. Sessions are in `~/Library/Application Support/dev.megabuild.picnest/Sessions/`.
- The app has its own repository, `picnest`. The Python tool is in `classifyimages` (user decision, 2026-10-23). See [[2026-10-23-picnest-split-plan]].
- Model: MobileCLIP S2 and the temporary values in `ClassifySettings.default` (`minScore` 0.22, `minMargin` 0.02, temperature 0.01). These values are provisional. Phase 0 Task 4, Steps 7-12, replaces them after the labeling test.
- No App Sandbox, with the hardened runtime on (section 8).
- Layers: the view models call services only. `LibraryService` owns the recent folders, the open flow, and the after-sort flow (section 9.1). `ThumbnailService` owns the thumbnail cache.
- After a sort (section 9.1): **Done** closes the session only after a finished sort. After a stop or a failure, the app stays in the Review screen. If the sort placed files, the toolbar shows **Undo Last Sort**.
- The app does not start a new sort for a folder whose last sort did not finish. It tells the user to click **Undo Last Sort** first (section 7.3, rule 6).
- While **Undo Last Sort** runs, the app does not open a folder, scan, sort, or start a second undo.
- **Undo Last Sort** in the recent folder list keeps the session. The user can open the folder again and sort without a new scan.
- If the user moves a sorted folder, the recent list shows "Sorted <date>" but no **Undo Last Sort**. Reason: the journal holds the old paths.
- If the user moves a folder after a sort that did not finish, the app does not open the folder. It tells the user to move the folder back to the old path and click **Undo Last Sort**. The session and the journal stay at the old path. (Final review I3.)
- For a folder whose last sort did not finish, the app shows the **Undo Last Sort** text at once. It does not ask "Start a new sort?". (Final review M7.)
- The destination must be outside the source folder (section 7.1). This replaces the earlier rule that allowed a destination in the source folder. (Final review I2.)
- The scan skips symbolic links. A sort would copy the link, not the photo. (Final review I5.)
- The app has 1 window. File > New Window is not in the menu. (Final review I1.)
- If the app cannot save the session, the Review screen shows an alert with **Try Again** and **OK**. The Sort summary shows the same text. (Final review I4.)
- The app does not quit while a sort or an undo runs. It shows "A sort is running. Stop it first, then quit." (Final review M4.)
- The build guide is `BUILD.md` ([[BUILD]]).

**User feedback (2026-10-22), user decisions:**

- Keep the recent folder list. The user can remove 1 folder or all folders from it (section 3.1).
- Rename format: date, category, and number (section 7.2).
- Find exact copies and similar photos. Keep 1, move the others to the Trash (section 3.6).
- Suggest new categories for "Not sure" photos. The user accepts each one (section 3.7).
- Move to Trash, not permanent delete, for duplicates and for selected photos (section 7.4).

**Builder decisions for the feedback:**

- Return opens Quick Look, the same as Space. The right-click menu also has **Open** for the default app (section 3.3).
- Move to Trash asks for no confirmation, as in Finder. ⌘Z puts photos back. **Clean Up All** asks for confirmation, because it can trash many photos.
- The reopen dialog of a sorted folder offers **Undo Last Sort** (section 9.1).
- `duplicateSimilarity` 0.95 is provisional, the same as the other phase 0 values.
- A suggestion needs at least 3 photos. The Sort sheet hint shows at 20 "Not sure" photos and 10% of the photos.
- If `trashItem` fails (for example on a volume with no Trash), the app does not delete the file. It shows "The photo could not be moved to the Trash: <reason>." and keeps the photo.
- The review undo stack is not saved when the app quits. After a restart, the user puts trashed photos back with Finder (**Put Back**).
- Rename applies only to files that the sort places. Photos left in the source folder keep their names.
- The key of a group marked **Not Duplicates** is the sorted list of its media IDs. If a rescan changes the group, the app shows it again.
- An exact-copy group is shown only under **Exact copies**. Similar groups never contain 2 photos of the same exact-copy group: the app uses the Keep photo of each exact group for the similar search.
- If the Keep photo of an exact group is also in a similar group, it is a Keep photo there too. Clean Up never moves the current Keep photo of an exact group to the Trash.
- If the Keep files of a similar group are not on the disk any more, Clean Up moves no photo of that group to the Trash.

**Builder decisions for the feedback of 2026-10-23:**

- The app saved 1 session with no categories (feedback 2026-10-23). The cause is not known. Rescan now repairs such a session (section 5.1).
- **Start Over…** is in the File menu, not in the toolbar, because the toolbar has no free space. It keeps the embedding cache, so a folder of 2,000 photos does not need new embeddings.
- The Suggest Categories sheet opens after a scan with the rule of the Sort sheet hint. The rule is at least 20 "Not sure" photos and at least 10% of the photos. One rule in the core serves both places.
- With the Everyday list, 10 of 10 suggestions for an art studio folder became "Group <n>". The best names were taken or scored less than `minScore`. With the Art studio list, all 10 got names. So the app uses 1 large list and never asks the user to select one.
- Apple Vision image labels were tested as a name source. They are too general (for example "people", "art"), so the app does not use them.

