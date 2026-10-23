---
id: picnest-split-plan
title: Move the macOS App into the Picnest Repository
type: plan
status: active
tags: [picnest, macos, open-source]
links:
  - "[[2026-10-21-macos-app-design]]"
  - "[[2026-10-21-macos-app-plan]]"
  - "[[BUILD]]"
---

# Move the macOS App into the Picnest Repository

The macOS app Picnest moves from the `classifyimages` repository to its own repository, `picnest`. The Python tool stays in `classifyimages`. See [[2026-10-21-macos-app-design]] for the app rules.

## Decisions

- App name: Picnest. Repository: `megabuild-dev/picnest`. (User decision, 2026-10-23.)
- Bundle ID: `dev.megabuild.picnest`. The test bundle ID is `dev.megabuild.picnest.tests`.
- The app has no earlier release. It needs no data migration.
- The core Swift package is `PicnestCore`.
- Links to the Python documents are web links to `megabuild-dev/classifyimages`.

## Branches

Main feature branch: `picnest-rename`. Each phase uses the sub-branch `feature/picnest-rename/phase-<n>-<description>`.

## Phases

- [x] **Phase 0: Split.** Clone `classifyimages`. Keep only the app files with `git filter-repo`. Move the app folder to the root.
- [x] **Phase 1: Names in the code.** Folders, Xcode target, scheme, Swift package, module imports, bundle ID, exported type ID, and Info.plist key use Picnest. All tests pass.
- [x] **Phase 2: Documents.** README, BUILD, CONTRIBUTING, notices, spec, plans, dictionary, CI, `.gitignore`, and `make-dmg.sh` use Picnest and the root layout.
- [x] **Phase 3: Clean `classifyimages`.** Remove the app files. Point the Python documents to `picnest`. Update its README and CI.

## Exit check

1. Core tests, app tests, and Python tests pass in each repository.
2. `scripts/make-dmg.sh` makes `Picnest <version>.dmg`.
3. In `picnest`, a case-insensitive search for the old app name and the old bundle ID finds nothing.
