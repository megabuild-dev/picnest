---
id: picnest-dictionary
title: Picnest Project Terms
type: dictionary
status: active
tags: [picnest, terms]
links:
  - "[[2026-10-21-macos-app-design]]"
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
| Manual pick | A photo that the user put in a category by hand in the app, or accepted from "Not sure". The app never changes it. |
| Example | The embedding of a manual pick. The app uses it to score other photos for the same category. |
| Not sure | The app name for an uncertain photo. |
| Session | The saved state of the app for 1 source folder. |
| Sort | The app name for CLI `apply`. |
| Review undo | ⌘Z in the app Review screen. It reverses 1 review change. It does not change files. |

See [CLI design](https://github.com/megabuild-dev/classifyimages/blob/main/docs/specs/2026-10-14-image-classifier-design.md) for the full design. See [[2026-10-21-macos-app-design]] for the macOS app.
