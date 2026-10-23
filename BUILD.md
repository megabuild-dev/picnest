---
id: picnest-build-guide
title: How to Build and Install Picnest
type: guide
status: active
tags: [picnest, macos, xcode, guide]
links:
  - "[[2026-10-21-macos-app-design]]"
  - "[[2026-10-21-macos-app-plan]]"
---

# How to Build and Install Picnest

Picnest is a macOS app that sorts a folder of photos into category folders. You can build the app on your Mac with Xcode, or install it from a DMG file. To build the app, you do not need a paid Apple Developer account. Read [[2026-10-21-macos-app-design]] for the full rules. Read [CLI guide](https://github.com/megabuild-dev/classifyimages/blob/main/docs/guides/classify-usage.md) for the command-line tool.

## Requirements

- macOS 15.0 or later.
- Xcode 16 or later.
- 200 MB of free disk space for the model files, plus 200 MB for the built app.
- 200 MB of free disk space in `~/Library/Caches`. At the first start, the app compiles the model there.

You do not need Homebrew or XcodeGen to build the app. The project file `Picnest.xcodeproj` is in git.

## Build and start the app

1. Install Xcode from the App Store. Open Xcode 1 time and accept the license.
2. Open Terminal in the project folder.
3. Download the model files: `scripts/fetch-models.sh s2`. The build stops with an error if the model files are missing.
4. Open `Picnest.xcodeproj` in Xcode.
5. In the Xcode toolbar, select the scheme "Picnest" and the run destination "My Mac".
6. Click **Run** (⌘R). Xcode builds the app and starts it.

The app uses the MobileCLIP S2 model. Without an argument, `fetch-models.sh` downloads all 4 model sizes (740 MB). The script skips files that are already on the Mac.

The project signs the app with "Sign to Run Locally". You do not select a team.

## Change the project file

Do these steps only after you change `project.yml`.

1. Install Homebrew from <https://brew.sh>.
2. Install XcodeGen: `brew install xcodegen`.
3. In the `macos` folder, run `xcodegen generate`.
4. Commit `project.yml` and `Picnest.xcodeproj` together.

## Copy the app to Applications

1. In Xcode, open the Project navigator (⌘1).
2. Open the group **Products**.
3. Right-click `Picnest.app` and select **Show in Finder**.
4. Quit the app that Xcode started.
5. Drag `Picnest.app` from the Finder window to `/Applications`.
6. Start Picnest from the Applications folder.

## Make a DMG to share

A DMG file holds the built app and a link to `/Applications`. Users drag the app to the link. Upload the DMG to the GitHub release page.

1. Download the model files: `scripts/fetch-models.sh s2`.
2. Set the version in `project.yml`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Then run `xcodegen generate`.
3. Run `scripts/make-dmg.sh`.
4. The script writes `build/Picnest <version>.dmg` and shows its SHA-256 checksum.

Without settings, the DMG has an ad hoc signature. macOS blocks the app on a different Mac until the user clicks **Open Anyway**. See [If macOS blocks the app](#if-macos-blocks-the-app).

### Sign and notarize the DMG

Do these steps only if you have a paid Apple Developer account ($99 per year). Then macOS opens the app with no warning.

1. In Xcode, open **Settings > Accounts > Manage Certificates**. Add a **Developer ID Application** certificate.
2. Make an app-specific password at <https://account.apple.com>.
3. Save the notary login 1 time: `xcrun notarytool store-credentials notary --apple-id <email> --team-id <TEAMID> --password <app-specific password>`.
4. Run the script with 2 settings:

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=notary scripts/make-dmg.sh
```

The script signs the app and the DMG, sends the DMG to Apple, and staples the ticket. The last check must show `accepted`.

## Publish a release on GitHub

1. Make the DMG. See [Make a DMG to share](#make-a-dmg-to-share).
2. Make a git tag with the same version, for example `v1.0`.
3. Run this command. Replace the version and the notes:

```bash
gh release create v1.0 "build/Picnest 1.0.dmg" --title "Picnest 1.0" --notes "First release."
```

GitHub accepts files up to 2 GB. The DMG with the S2 model is 180 MB.

## If macOS blocks the app

- If you built the app and macOS does not open it, build it again on this Mac. Then copy it to `/Applications` again.
- If you installed the app from a DMG without notarization, macOS shows "Apple could not verify". Click **Done**. Open **System Settings > Privacy & Security**. Find the Picnest message and click **Open Anyway**. Then type your Mac password.
- Alternative: run `xattr -dr com.apple.quarantine "/Applications/Picnest.app"` in Terminal. Do this only for a DMG from the official release page.
- macOS asks 1 time for access to Desktop, Documents, or Downloads. Click **Allow**.
- If you clicked **Don't Allow**, open **System Settings > Privacy & Security > Files and Folders**. Turn on access for Picnest.

## Update the app

1. Get the new project files.
2. Run `scripts/fetch-models.sh s2` again. It downloads only missing files.
3. In Xcode, click **Run**.
4. Copy the new `Picnest.app` to `/Applications`. Replace the old app.

Your sessions stay in `~/Library/Application Support/dev.megabuild.picnest/`. An update does not change them.

## Run the tests

The app tests build the app, and the app build needs the model files. Download them first with `scripts/fetch-models.sh s2`. The core tests do not need the model files.

1. Run the core tests: `swift test --package-path PicnestCore`.
2. Run the app tests: `xcodebuild test -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS'`.

## Final check with real photos

Do this check 1 time, before the family uses the app. It is the exit check of phase 6 in [[2026-10-21-macos-app-plan]].

Do the labeling test first: Task 4, Steps 7-12 in [[2026-10-21-macos-app-plan]]. That test selects the model size and the classify settings. Until then, the app uses S2 and temporary settings.

To compare a folder before and after a step, run this command in Terminal. Replace `<folder>` and `<file>`:

```bash
cd "<folder>" && find . -type f -exec shasum -a 256 {} + | sort -k 2 > "<file>"
```

Then compare 2 lists with `diff <file 1> <file 2>`. No output means that the folders are the same.

1. Copy 500 photos from the Zalo folder to a new folder, for example `~/Desktop/Check`. Do not use the original folder.
2. Make a list of the new folder: `before.txt`. Save the list outside the folder.
3. Start Picnest. Drop the new folder on the window.
4. Write down the scan time from the start of the scan to the Review screen.
5. Rename 1 category.
6. Move 5 photos to a different category.
7. Open **Not sure**. Accept 1 group.
8. Quit the app (⌘Q). Start it again. Open the folder from the recent list.
9. Make sure that the new name, the 5 moved photos, and the accepted group are still there.
10. Click **Sort Photos…**. Select **Copy**. Click **Sort**. When the sort ends, click **Done**.
11. On the Welcome screen, click **Undo Last Sort** for the folder.
12. Make a new list of the folder and compare it with `before.txt`. Make sure that `Check - sorted` does not exist.
13. Open the folder again. Click **Sort Photos…**. Select **Move**. Turn on **Make date sub-folders**.
14. Click **Move <N> Photos**, then click **Move** to confirm. When the sort ends, click **Done**.
15. Click **Undo Last Sort** for the folder.
16. Make a new list of the folder and compare it with `before.txt`. Make sure that `Check - sorted` does not exist.
17. Write the scan time for 500 photos in [[2026-10-21-macos-app-plan]], at Task 19.

If a step fails, stop. Keep the folder and the session folder for the bug report.
