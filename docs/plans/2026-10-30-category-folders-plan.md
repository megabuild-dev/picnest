---
id: category-folders-plan
title: Keep Category Folders in Step with Categories
type: plan
status: active
tags: [review, categories, folders, trash]
links:
  - "[[2026-10-21-macos-app-design]]"
  - "[[2026-10-21-macos-app-plan]]"
---

# Keep Category Folders in Step with Categories

A category has a folder in the source folder. The folder follows the category when the user creates, renames, or deletes it. See [[2026-10-21-macos-app-design]] sections 3.3 and 7.2.

## Decisions

- The user wants a new category to make its folder. (User decision, 2026-10-30.)
- The user wants a rename to rename the folder. (User decision, 2026-10-30.)
- The user wants a delete to ask first, and to warn that the photos and the folder go. (User decision, 2026-10-30.)
- Delete moves the photos to the Trash. It does not delete them. (User decision, 2026-10-30.)
- `Category.folderName` stores the folder name. The planner, Reveal, and Done read it. Old sessions have no value, so the app uses the computed name.
- A rename that moves files changes the ID of each photo in the folder. The app re-keys the session as Done does. It clears the undo history, because old snapshots hold old IDs.
- Merge does not move folders. The folder of the merged category stays. (Builder decision.)
- If the folder holds files that the session does not track, delete keeps the folder.

## Branches

Main feature branch: `category-folders`. Each phase uses the sub-branch `feature/category-folders/phase-<n>-<description>`. The work starts from `fix/reveal-category-in-finder`, because it needs `SortPlanner.folderNames`.

## Phases

- [x] Phase 1: store `folderName` on `Category`, and make the folder when a category is created.
- [x] Phase 2: rename the folder when a category is renamed, and re-key the session.
- [ ] Phase 3: confirm a delete, move the photos to the Trash, and remove the folder.
- [ ] Phase 4: update [[2026-10-21-macos-app-design]] sections 3.3 and 7.2.
