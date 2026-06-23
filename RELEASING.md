# Versioning and releases

This document describes how ShatterBreak versions are computed and how to cut a
release. It is maintainer-facing: cutting releases is a manual step performed by
the maintainer.

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

Version defaults live in `Config/AppVersion.xcconfig`; the scheme pre-action
writes `Config/Version.xcconfig` on each build to override them.

## Cutting a release

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
