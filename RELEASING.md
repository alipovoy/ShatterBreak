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
- The **bump happens once, at release time**, and **you choose it** by naming the
  tag of the release you draft. `Scripts/compute-version.sh --mode next-tag` is an
  optional helper that *suggests* the next version from the Conventional Commit
  subjects merged since the last tag, following SemVer:
  - a `feat:` subject suggests a **minor** bump (`1.2.3 → 1.3.0`),
  - a `fix:`/`perf:`/other subject suggests a **patch** bump (`1.2.3 → 1.2.4`),
  - a `!` marker (e.g. `feat!:`) or a `BREAKING CHANGE` footer suggests a
    **major** bump (`1.2.3 → 2.0.0`).

The highest applicable bump wins (one `feat:` among several `fix:`es yields a
minor bump), and the suggestion is relative to the last tag. It is only a
suggestion — the version is whatever tag you publish, so double-check it before
shipping. Nothing is tagged or published until you decide to cut a release.

Conventional Commits keep the history changelog-ready and make the release bump
trustworthy. The repository squash-merges only, so the **PR title** becomes the
commit on `main` and drives the bump (keep *Settings → General → "Default to PR
title for squash merge commits"* enabled so it carries through).

Every commit subject follows the convention too, not just the PR title, so
history reads canonically wherever it lands — a rebase-merge, or a merge between
non-`main` branches. The commit-msg hook in [`.githooks/`](./.githooks) rejects a
bad subject at commit time, and the `PR Conventions` workflow
(`.github/workflows/pr-conventions.yml`) checks the title and every commit. Merge
commits are skipped; subjects git writes itself (`fixup!`, `Revert "…"`) are not.
The rule is `Scripts/lint-commit-subject.sh`; `compute-version.sh` reads the
subjects it produces with its own, looser pattern.

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

Releases are cut by hand from the GitHub UI. The **Release Build** workflow
(`.github/workflows/release.yml`) then attaches the built artifacts. There is a
single trigger — publishing a release — so a release produces exactly one build.

1. *(Optional)* Ask for the suggested next version:

   ```sh
   Scripts/compute-version.sh --mode next-tag                # e.g. v1.3.0 (auto)
   Scripts/compute-version.sh --mode next-tag --bump minor   # force minor
   Scripts/compute-version.sh --mode next-tag --bump major   # force major
   Scripts/compute-version.sh --mode next-tag --bump patch   # force patch
   ```

2. On GitHub, go to **Releases → Draft a new release**.
3. Under **Choose a tag**, type the new `vX.Y.Z` tag (e.g. `v1.3.0`) and select
   *Create new tag on publish*. Target `main` (or the commit you want to ship).
4. Click **Generate release notes** — GitHub builds the changelog from the PRs
   and commits merged since the last release (the history is Conventional-Commit
   clean). Edit the notes if you like.
5. Click **Publish release**.

Publishing fires **Release Build** once: it checks out the tagged commit, runs
the tests, archives, ad-hoc signs, and uploads `ShatterBreak-vX.Y.Z.zip` (plus the
dSYM) as assets on that release. When it finishes, the release in the Releases
section has both your notes and the downloadable build.

Release tags must be a fully pinned `vMAJOR.MINOR.PATCH` (e.g. `v1.4.5`) or a
pre-release of one (see below). A tag without the `v` prefix is rejected, because
the baseline only honors `v*` tags. If no tags exist, semver falls back to
`1.0.0` (defined in `Scripts/compute-version.sh`).

> **Don't push a bare `vX.Y.Z` tag and expect a build.** Nothing is wired to a
> tag push — releases are built only when you *publish a release* in the UI. This
> is deliberate: it is what keeps a release to exactly one build.

### Re-running a build

If a Release Build fails (e.g. a transient CI error) after the release is already
published, don't unpublish it. Re-run from the Actions tab: **Release Build → Run
workflow**, enter the existing tag in **release_tag**, and run. It rebuilds and
re-uploads the assets to that release (`--clobber` overwrites any partial
uploads).

### Pre-release tags (RC / beta)

To ship a release candidate or beta, draft the release exactly as above but use a
[SemVer §9 pre-release](https://semver.org/#spec-item-9) tag — a `vX.Y.Z`
followed by `-` and dot-separated identifiers of ASCII alphanumerics and hyphens
(e.g. `v1.3.0-rc.1`, `v2.0.0-beta.2`) — and check **Set as a pre-release** before
publishing:

```sh
Scripts/compute-version.sh --mode next-tag --bump minor --pre rc.1  # v1.3.0-rc.1
```

Publishing builds and uploads artifacts with the marketing version `1.3.0-rc.1`
verbatim — the same path as a final release.

**Pre-releases are intentionally not baselines.** A pre-release tag never becomes
the version that dev/CI builds report and never participates in the next-version
computation: only strict `vX.Y.Z` tags do. This keeps the model deterministic and
matches SemVer precedence — `1.3.0-rc.1` sorts *below* its final `1.3.0`:

- While `v1.3.0-rc.1` is the only new tag past the last release `v1.2.3`, dev/CI
  builds still report `1.2.3`, and `next-tag` keeps deriving `1.3.x` from the
  commits since `v1.2.3` (the RC does not advance or freeze the baseline).
- Once you cut the final `v1.3.0`, it becomes the baseline as usual; the earlier
  `v1.3.0-rc.1` has no further effect.

`--pre` works with auto-detected or forced (`--bump`) levels. Build metadata
(`+sha`, SemVer §10) is out of scope. `CFBundleVersion` (the build number) is
unaffected — pre-releases only change the marketing string.

## Signing so permissions survive updates

macOS binds the Screen Recording grant to the app's code-signing **Designated
Requirement (DR)**. An ad-hoc signature has a DR equal to the binary's `cdhash`, so
every build looks like a new app and the user must re-add it under *System Settings >
Privacy & Security > Screen Recording*. A stable identity gives a constant DR and the
grant carries over. Builds are un-notarized either way, so the quarantine step (README)
is unchanged.

### Which identity signs a build

| Mode | Applies to | Update-stable |
|------|------------|---------------|
| **Ad-hoc** | CI and published builds. No certificate, no setup. | No |
| **Team** | Your own builds from source, once a team is set ([below](#local-team-signing)). Xcode signs with *Apple Development*; a free personal team works. | Yes — the DR pins the certificate's common name, so it normally survives certificate renewal |
| **Self-signed** | A downloaded build you re-sign yourself ([README](./README.md#stable-signing-for-a-downloaded-build)). | Yes — until the certificate is renewed: a new certificate has a new DR, costing one re-add a year |

**Published builds stay ad-hoc, deliberately.** CI has no certificate, and giving it one
means a key in repository secrets. Trying the app should not require certificate
setup; the cost lands on updates, where the README explains the re-add. Decided in
[#100](https://github.com/alipovoy/ShatterBreak/issues/100).

### Local team signing

Without a team, Xcode signs local builds ad-hoc too, so every Debug rebuild drops the
Screen Recording grant. Only CI turns signing off (`CODE_SIGNING_ALLOWED=NO`). Setting a
team fixes that. The settings stay out of the repository, in a git-ignored xcconfig that
`Config/Signing.xcconfig` pulls in with `#include?`, so a missing file is not an error:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig   # set DEVELOPMENT_TEAM
xcodegen generate
```

The example also asks for a secure timestamp on Release. Xcode adds none, and without one
the signature stops validating the day the development certificate expires.

Find the Team ID in *Xcode > Settings > Accounts*, or, for a free team, from the
certificate — the `OU` field:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

Not the parenthesized suffix from `security find-identity`, which is not the Team ID.
The setting applies at project level so the test target inherits it; no
`PROVISIONING_PROFILE_SPECIFIER` is needed, as the entitlements are sandbox-only.

Confirm the DR is not a bare `cdhash`:

```bash
codesign -d --requirements - path/to/ShatterBreak.app
```

Team signing is for your own builds; builds for other people come from CI.
