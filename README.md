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
[Conventional Commits](https://www.conventionalcommits.org). **The version is
decoupled from PR merges:** it reflects releases, not individual PRs.

- **`X.Y.Z`** come from the latest `vX.Y.Z` git tag (the last release). Dev and
  CI builds report that version, so it **stays stable as PRs land on `main`** —
  it only changes when you cut a new release.
- The **bump happens once, at release time**. The `Cut Release` workflow (or
  `Scripts/compute-version.sh --mode next-tag`) derives it from the Conventional
  Commit subjects merged since the last tag:
  - a `feat:` subject bumps the **minor** (`1.2.3 → 1.3.0`),
  - a `fix:`/`perf:`/other subject bumps the **patch** (`1.2.3 → 1.2.4`),
  - a `!` marker (e.g. `feat!:`) or a `BREAKING CHANGE` footer bumps the
    **major** (`1.2.3 → 2.0.0`).

The highest applicable bump wins (one `feat:` among several `fix:`es yields a
minor bump), and the bump is relative to the last tag. Nothing is tagged or
published until you decide to cut a release.

Conventional Commits keep the history changelog-ready and make the release bump
trustworthy. Which string drives the bump depends on the merge method:

- **squash-merge** uses the **PR title** (enable *Settings → General → "Default
  to PR title for squash merge commits"* so it carries through),
- **rebase-merge** replays your **commit subjects** verbatim.

So both the PR title and every commit subject must be valid Conventional
Commits. The `PR Conventions` workflow (`.github/workflows/pr-conventions.yml`)
enforces this with two checks — one for the title, one for the commits — so the
bump is trustworthy whichever merge method you use.

In the table below, `{semver}` is the **last released** `vX.Y.Z` (or `1.0.0`
before the first tag) — not the next one.

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

When you're ready to ship, run the **Cut Release** workflow
(`.github/workflows/cut-release.yml`) from the Actions tab. Pick a bump:

- **`auto`** (default) derives the bump from the Conventional Commits since the
  last tag,
- **`patch` / `minor` / `major`** force a level relative to the last release.

It computes the next `vX.Y.Z`, creates and pushes the tag, then dispatches
**Release Build** (`release.yml`) at that tag to archive and upload the
artifacts. One run takes you from "accumulated PRs on `main`" to a tagged,
built release.

Prefer the command line? Ask the script which tag to create, then tag it
yourself — pushing a `vX.Y.Z` tag triggers `release.yml` directly:

```sh
Scripts/compute-version.sh --mode next-tag                # e.g. v1.3.0 (auto)
Scripts/compute-version.sh --mode next-tag --bump minor   # force minor
Scripts/compute-version.sh --mode next-tag --bump major   # force major
Scripts/compute-version.sh --mode next-tag --bump patch   # force patch

git tag -a v1.3.0 -m v1.3.0 && git push origin v1.3.0
```

Release tags must be a fully pinned `vMAJOR.MINOR.PATCH` (e.g. `v1.4.5`). A tag
without the `v` prefix is rejected, because the baseline only honors `v*` tags.
If no tags exist, semver falls back to `1.0.0` (defined in
`Scripts/compute-version.sh`).

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
