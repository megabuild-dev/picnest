---
id: picnest-dictionary
title: Picnest Project Terms
type: dictionary
status: active
tags: [picnest, terms]
links:
  - "[[2026-10-21-macos-app-design]]"
  - "[[2026-11-01-ui-redesign-design]]"
---

# Picnest Project Terms

| Term | Meaning |
|------|---------|
| Source folder | The folder that the user gives to the tool. The tool never changes this folder in copy mode. |
| Output folder | The folder that receives the sorted files. Default: `<source folder> - sorted`, next to the source folder. |
| Media file | One image or video file that the tool processes. |
| Category | One content group. It has a slug name and a text prompt for CLIP. |
| Prompt | The English sentence that describes a category to CLIP. |
| Embedding | The vector that CLIP makes from one image or one prompt. |
| Cluster | One group of similar images that `discover` finds. A cluster becomes a proposed category. |
| Plan | The file `plan.csv`. It lists the source path, destination path, and score for each media file. |
| Journal | The file `journal.jsonl`. It records each file operation that `apply` does, so that `undo` can reverse it. |
| Uncertain | The status of an image whose best score is below the threshold or whose top 2 scores are too close. |
| Work folder | The folder `.classify/` inside the output folder. It holds the cache, plan, journal, and review page. |
| Manual pick | A photo that the user put in a category by hand in the app, or accepted from Needs Review. The app never changes it. |
| Example | The embedding of a manual pick. The app uses it to score other photos for the same category. |
| Not sure | The name of the sorted folder on disk that holds uncertain photos. The app shows "Needs Review" for them. |
| Session | The saved state of the app for 1 source folder. |
| Sort | The app name for CLI `apply`. |
| Review undo | ⌘Z in the app Review screen. It reverses 1 review change. It does not change files. |
| Appearance | The Settings choice of System, Light, or Dark colors. |
| Language setting | The Settings choice of System, English, or Tiếng Việt. The app uses it on the next launch. |
| String Catalog | The file `Picnest/Localizable.xcstrings`. It holds all UI text and its translations. |
| Chosen by you | The filter for photos that the user decided. It replaces "Changed by you". |
| Needs Review | The app name for photos that the tool could not sort with confidence. The sorted folder for them is "Not sure". |
| Favorite | A flag on a photo. It does not move a file. |
| Collection | A named group of photos. It does not move a file. |
| Recently Deleted | The sidebar list of photos that the user moved to the Trash. It does not move a file. |
| Put Back | The action that returns a photo from Recently Deleted. It moves the file from the macOS Trash to its original path. |
| Photo Editor | The screen where the user crops, straightens, rotates, flips, and adjusts a photo. It changes no file of the source folder. The only output is the edited copy. |
| Original | The photo file in the source folder. The Photo Editor never changes it. The editor shows it with the text "Original stays unchanged". |
| Edited copy | The new file that **Export edited copy** writes. It is the only file the editor makes. The user chooses where to save it. |
| Export edited copy | The action that saves the edit as a new file. It changes no file of the source folder, except the new copy where the user saves it. |
| Layout Editor | The screen where the user puts photos on pages and exports them. It changes no photo. The output is a PNG or PDF file. |
| Layout | The document that the Layout Editor edits. It holds the kind, the paper size, the spacing, the background, and the ordered photo ids. It changes no photo. |
| Contact sheet | A page of photos in a grid, each shown whole. Export makes a PNG or PDF file. No photo changes. |
| Collage | A page where photos fill the cells of a template. The app crops each photo to its cell on the page only. No photo changes. |
| Layout draft | The one layout that `Session` saves for a source folder. The app saves it by itself. **Start Over** deletes it. No photo changes. |
| Paper size | The page size of a layout, for example A4 or Letter, in landscape or portrait. It sets the size of the exported file. No photo changes. |

See [CLI design](https://github.com/megabuild-dev/classifyimages/blob/main/docs/specs/2026-10-14-image-classifier-design.md) for the full design. See [[2026-10-21-macos-app-design]] for the macOS app.
