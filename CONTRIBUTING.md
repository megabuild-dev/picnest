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
