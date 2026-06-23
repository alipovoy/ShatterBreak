# Contributing to ShatterBreak

Thanks for your interest in improving ShatterBreak! This guide covers how to build
the app, run the tests, and submit changes.

By participating in this project you agree to abide by our
[Code of Conduct](./CODE_OF_CONDUCT.md).

## Prerequisites

* macOS 15.0 or later
* Xcode with the macOS 15 SDK (CI uses Xcode 26.5)
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) for generating the Xcode project
* [SwiftLint](https://github.com/realm/SwiftLint) for linting (see [Linting](#linting))

Install both with Homebrew:

```bash
brew install xcodegen swiftlint
```

## Project layout

This repository uses `project.yml` as the source of truth for the Xcode project.
`ShatterBreak.xcodeproj` is **generated** and must not be edited by hand — regenerate
it with XcodeGen after changing `project.yml`.

* `ShatterBreak/` — application source
* `ShatterBreakTests/` — unit tests
* `Config/` — version and build configuration
* `Scripts/` — build helper scripts (e.g. `compute-version.sh`)
* `project.yml` — XcodeGen project definition
* `requirements.md` — behavior blueprint for the app as it exists today
* `RELEASING.md` — version scheme and release-cutting process (maintainer-facing)

## Building

Generate the project, then build:

```bash
xcodegen generate
xcodebuild -project ShatterBreak.xcodeproj -scheme ShatterBreak build
```

You can also open `ShatterBreak.xcodeproj` in Xcode, select the `ShatterBreak`
scheme, and build and run from there.

## Running tests

```bash
xcodegen generate
xcodebuild -project ShatterBreak.xcodeproj -scheme ShatterBreak test
```

CI runs the same `xcodebuild test` flow on every pull request via
[`.github/workflows/build-and-test.yml`](./.github/workflows/build-and-test.yml).
Please make sure tests pass locally before opening a PR.

## Linting

The project is linted with [SwiftLint](https://github.com/realm/SwiftLint), configured
in [`.swiftlint.yml`](./.swiftlint.yml). CI fails the build on any warning, so please
lint locally before opening a PR.

Install SwiftLint with Homebrew:

```bash
brew install swiftlint
```

Run it from the repository root (this matches the CI step exactly):

```bash
swiftlint lint --strict
```

Many issues can be fixed automatically:

```bash
swiftlint --fix
```

### Pre-commit hook

A pre-commit hook that runs SwiftLint lives in [`.githooks/`](./.githooks). Enable it
once per clone by pointing Git at that directory:

```bash
git config core.hooksPath .githooks
```

After that, every `git commit` runs `swiftlint lint --strict` and blocks the commit on
violations. If SwiftLint is not installed the hook warns and lets the commit through —
CI still enforces it.

## Coding guidelines

ShatterBreak is a modern Swift 6 / SwiftUI codebase. New code is expected to follow
these conventions:

* Targets are macOS 15.0 or later, Swift 6 with strict concurrency.
* Prefer `@Observable` classes with `@State` / `@Bindable` / `@Environment` over
  `ObservableObject` and the legacy property wrappers.
* Always prefer async/await APIs over closure-based variants.
* Prefer modern Foundation and SwiftUI APIs (`FormatStyle` over `DateFormatter`,
  `foregroundStyle` over `foregroundColor`, and so on).
* Put view logic into view models so it can be unit-tested.
* Write unit tests for core application logic; only add UI tests when unit tests
  are not possible.

Run SwiftLint and make sure it reports no warnings or errors before committing — see
[Linting](#linting) above.

## Pull request workflow

1. Fork the repository and create a topic branch from `main`
   (e.g. `feature/short-description` or `fix/short-description`).
2. Make your change, keeping commits focused and with clear messages.
3. Add or update tests covering your change.
4. Run `xcodebuild test` and `swiftlint lint --strict` and confirm both pass.
5. Open a pull request against `main` describing **what** changed and **why**.
   Link any related issue (e.g. `Closes #123`).

For larger or architectural changes, please open an issue first to discuss the
approach before investing significant work.

## Reporting bugs and requesting features

Use the [GitHub issue tracker](https://github.com/alipovoy/ShatterBreak/issues).
For bug reports, include your macOS version, steps to reproduce, what you expected,
and what actually happened. Security issues should **not** be filed as public
issues — see [SECURITY.md](./SECURITY.md).

## Distribution note

ShatterBreak is not distributed through Apple channels and is not signed with a
Developer ID or notarized. Release builds are ad-hoc signed, and users remove the
Gatekeeper quarantine attribute manually (see the README). Please do not add
notarization, Developer ID signing, or App Store steps in contributions.
