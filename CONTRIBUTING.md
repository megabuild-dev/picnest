# Contributing to Picnest

Thank you for your help. This guide tells you how to report a problem, set up the project, and send a change.

## Report a bug or ask for a feature

1. Search the [issues](../../issues) first. Maybe somebody reported it already.
2. Open a new issue with the bug or feature template.
3. For a bug, give your macOS version, the app version, and the steps that cause the problem.

Do not attach private photos. Describe the photos, or use photos that you can share.

For a security problem, do not open a public issue. Read [SECURITY.md](SECURITY.md).

## Set up the project

1. Install Xcode 16 or later.
2. Run `scripts/fetch-models.sh s2`.
3. Open `Picnest.xcodeproj` and click Run.

[BUILD.md](BUILD.md) has the full steps.

## Run the tests

Run both test sets before you send a pull request:

```bash
swift test --package-path PicnestCore
xcodebuild test -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS'
```

The app tests need the model files. The core tests do not.

## Translate Picnest

All UI text is in `Picnest/Localizable.xcstrings`. English is the source language, and `vi` is the first translation.

### Add a language

1. Open `Picnest/Localizable.xcstrings` in Xcode.
2. Click the **+** button under the language list. Choose your language.
3. Fill in every key for the new language. Set each value to the state `Translated`.
4. Run `xcodegen generate`. It reads the languages from the catalog and updates `knownRegions` in the project file.
5. Add the language to the Settings picker. See "Show the language in Settings".
6. Run `PicnestTests/CatalogTests` (see "Check the catalog"). It reports each key that your language lacks.

### Keep the catalog in step with the code

After you add or change a text in Swift, build the app. Then run `python3 -I scripts/sync-string-catalog.py`.
The script adds each new key to the catalog. It marks each key that the code no longer uses as `stale`.
Give every new key a `vi` value with the state `translated`.
Run `python3 -I scripts/sync-string-catalog.py --check` to see the differences without a change.
The `--check` option changes no file. It shows the keys that the catalog lacks and the keys that the code no longer uses. It exits with code 1 when it finds a difference.

The catalog tests check only the keys that are already in the catalog. They cannot find a text in the code that the catalog lacks.
Run `python3 -I scripts/sync-string-catalog.py --check` before each commit. It finds the code texts that the catalog lacks.

### Check the catalog

Run the catalog tests:

```bash
xcodebuild test -project Picnest.xcodeproj -scheme Picnest -destination 'platform=macOS' -only-testing:PicnestTests/CatalogTests
```

The tests check every language in the catalog, not only `vi`. English is the source, so the tests skip it.
A test fails when a key has no `translated` value in any one language. The failure message names the language and the keys.
A key with `shouldTranslate` set to `false` is skipped. The tests also fail when the catalog has a `stale` key.

### Show the language in Settings

Settings > Language lets the user pick **System**, **English**, or **Tiếng Việt**. To add a language, change `AppLanguage` in `Picnest/Settings/LanguageStore.swift`:

1. Add a `case` with the language code, for example `case system, en, vi, fr`.
2. Add a line to `displayName` with the name of the language in that language, for example `case .fr: "Français"`. Do not translate this name.

`AppLanguage` is a `CaseIterable` enum, so the picker shows the new case with no other change. `LanguageStoreTests` shows how to test it.

### Test the layout

Long text can break a layout. Run the app with a long pseudo-language:

1. Choose **Product > Scheme > Edit Scheme**.
2. Select **Run**, then the **Options** tab.
3. Set **App Language** to **Double-Length Pseudolanguage**.
4. Click Run. Look for clipped or overlapping text.

### Rules

- Settings > Language picks English or Tiếng Việt. A new language also needs an entry in `AppLanguage`.
- Category names and CLIP prompts are data. Never translate them.
- A plural key needs the variants `one` and `other`. Add more variants only when your language needs them.

## Code rules

- **Layers.** Code flows UI → services → repositories → system APIs. Views have no business logic. Services do not read files or call Core ML directly.
- **No copies.** Search for an existing type or view before you add a new one. Move shared code to 1 place.
- **Types first.** A new domain concept gets a type in `PicnestCore` before other code uses it.
- **Tests.** Add or change a test for each change of behavior.
- **Project file.** If you change `project.yml`, run `xcodegen generate`. Commit both files together.

## Documentation rules

The files in `docs/` and `BUILD.md` use YAML frontmatter (`id`, `title`, `type`, `status`, `tags`, `links`) and Simplified Technical English:

- Use active voice and short sentences: 20 words or fewer for steps.
- Use 1 word for 1 meaning, for example "show", not "display".
- Link related documents with `[[file-name]]`.
- Update an existing document. Do not make a second copy.

## Send a pull request

1. Fork the repository and make a branch from `main`, for example `fix/sort-sheet-crash`.
2. Keep each pull request to 1 topic.
3. Write commit messages like `fix(review): keep manual picks after rescan`.
4. Fill in the pull request template.

By contributing, you agree that your contribution is under the [MIT License](LICENSE).
