# ShatterBreak

ShatterBreak is a native macOS menu bar app for structured focus and break cycles.

It runs as a menu bar utility, lets you start a focus session, and then interrupts you with fullscreen break overlays when the work timer ends. The app supports a screenshot-based "shatter" effect, a simpler dark overlay mode, optional postpone, manual return after a break, and sleep/wake-aware timer behavior.

## Overview
ShatterBreak is built as a small macOS utility with a strong focus on system integration:

* menu bar-first workflow
* fullscreen break overlays on all connected displays
* optional screenshot-based shatter effect using ScreenCaptureKit
* soft overlay mode that keeps the menu bar reachable
* hard overlay mode that covers the menu bar
* configurable work and rest durations
* optional postpone during breaks
* automatic or manual restart after breaks
* optional timer text in the menu bar
* sleep/wake handling for active timers

## Requirements
* macOS 15.0 or later
* Xcode with the macOS 15 SDK
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) for generating the Xcode project

Screen recording permission is required only for the `Shatter` visual effect. If permission is not granted, the app still works and falls back to the plain overlay experience.

## Build
This repository uses `project.yml` as the source of truth. The Xcode project must be generated locally with XcodeGen.

### Install XcodeGen
If you use Homebrew:

```bash
brew install xcodegen
```

### Generate the project
From the repository root:

```bash
xcodegen generate
```

This creates `ShatterBreak.xcodeproj` locally. Version defaults live in `Config/AppVersion.xcconfig`; the scheme pre-action writes `Config/Version.xcconfig` on each build to override them.

### Build in Xcode
1. Generate the project with XcodeGen.
2. Open `ShatterBreak.xcodeproj`.
3. Select the `ShatterBreak` scheme.
4. Build and run the app.

### From the command line
```bash
xcodegen generate
xcodebuild -project ShatterBreak.xcodeproj -scheme ShatterBreak build
```

### Run tests
```bash
xcodegen generate
xcodebuild -project ShatterBreak.xcodeproj -scheme ShatterBreak test
```

## Versioning

App version strings are computed automatically by `Scripts/compute-version.sh`,
following [Semantic Versioning](https://semver.org) and
[Conventional Commits](https://www.conventionalcommits.org):

- **`X.Y.Z`** come from the latest `vX.Y.Z` git tag (the last release).
- The **next version is derived from the commit subjects merged since that tag**:
  - a `feat:` subject bumps the **minor** (`1.2.3 → 1.3.0`),
  - a `fix:`/`perf:`/other subject bumps the **patch** (`1.2.3 → 1.2.4`),
  - a `!` marker (e.g. `feat!:`) or a `BREAKING CHANGE` footer bumps the
    **major** (`1.2.3 → 2.0.0`).

So the version you see in a dev build is *the version the next release will be*.
The highest applicable bump wins (one `feat:` among several `fix:`es yields a
minor bump), and the bump is relative to the last tag — it does not stack across
intermediate builds. Releases stay **manual**: nothing is tagged or published
until you decide to cut a release.

Because we squash-merge, each PR's title becomes the commit subject that drives
this, so **PR titles must be valid Conventional Commits** — enforced by the
`PR Title` check (`.github/workflows/pr-title.yml`). For the title to carry
through, enable *Settings → General → "Default to PR title for squash merge
commits"* on the repository.

| Build context | Version format | Example |
|---------------|----------------|---------|
| Local Debug (Xcode Run/Build) | `{semver}-dev` | `1.3.0-dev` |
| Local Test (`xcodebuild test`) | `{semver}-test` | `1.3.0-test` |
| Local Archive | `{semver}-local` | `1.3.0-local` |
| GitHub CI (PR/push) | `{semver}-test` | `1.3.0-test` |
| GitHub Release | `{semver}` | `1.3.0` |

The build number (`CFBundleVersion`) is the commit count locally and the CI run
number in Actions, so every build is uniquely identifiable even when the
marketing version is unchanged. The 7-character build hash is stored separately
in the `AppBuildHash` Info.plist key.

### Cutting a release

Ask the script which tag to create — it reads the merged PRs and applies the
right bump automatically:

```sh
# Auto: derive the bump from the Conventional Commits since the last tag
Scripts/compute-version.sh --mode next-tag                # e.g. v1.3.0
```

To deviate from what the commits imply, force a level (relative to the last
release baseline):

```sh
Scripts/compute-version.sh --mode next-tag --bump minor   # force minor
Scripts/compute-version.sh --mode next-tag --bump major   # force major
Scripts/compute-version.sh --mode next-tag --bump patch   # force patch
```

Create and push the printed tag, then publish a GitHub Release for it —
`release.yml` builds and uploads the artifacts using the tag as the version.

Release tags must start with `v` and be either `vMAJOR.MINOR` (a baseline whose
patch starts at `0` — e.g. `v1.2` ships as `1.2.0`) or a fully pinned
`vMAJOR.MINOR.PATCH`. A tag without the `v` prefix is rejected, because the
baseline only honors `v*` tags. If no tags exist, semver falls back to `1.0.0`
(defined in `Scripts/compute-version.sh`).

## Running quarantined builds
macOS marks unsigned app as quarantined, remove the quarantine attribute before launching it:

```bash
xattr -dr com.apple.quarantine ShatterBreak.app
```

## How to Use
1. Launch the app and find the `ShatterBreak` icon in the macOS menu bar.
2. Open the menu bar popover and set `Work Duration` and `Rest Duration`.
3. Press `Start Focus` to begin a focus session.
4. When the work timer ends, ShatterBreak shows a break overlay on all connected screens.
5. During a break you can:
   * wait for the break to finish
   * use `Postpone` if that option is enabled and still available for the current cycle
   * return manually with `I'm back` if manual restart mode is enabled
6. Use `Preferences` to change the visual effect, enable soft overlay, allow postpone, and control menu bar timer display.

## Preferences
The current app supports these settings:

* `Play Sound`
* `Effect Type`: `Shatter` or `Overlay`
* `Soft Overlay (allows menu bar access)`
* `Allow Postpone`
* `Start work after break ends`: `Automatic` or `Manual`
* `Show timer in menu bar`

## Project Notes

The behavior blueprint for the app is documented in [requirements.md](./requirements.md).

The Xcode project definition lives in [project.yml](./project.yml).

## AI Assistance
This project was developed with AI assistance.

Different coding assistants and model providers were used over time, including tools such as GitHub Copilot, Anthropic Claude models, Google Gemini models, OpenAI ChatGPT models and locally run models through Ollama. The exact mix changed during development.

## License
This project is released under the BSD 3-Clause License.

See [LICENSE](./LICENSE) for the full text.
