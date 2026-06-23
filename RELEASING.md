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
the tests, archives, signs, and uploads `ShatterBreak-vX.Y.Z.zip` (plus the
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

The `Shatter` effect needs Screen Recording permission. macOS ties that grant to
the app's code-signing **Designated Requirement (DR)**. An ad-hoc signature
(`codesign --sign -`, what CI produces) has a DR equal to the binary's `cdhash`,
which changes on every build — so each new version looks like a different app and
the user has to re-add it under *System Settings > Privacy & Security > Screen
Recording* after every update.

Signing with a **stable self-signed certificate that you create once and reuse**
gives a constant DR (`identifier "…" and certificate leaf = H"…"`), so the grant
carries over across updates (at most a one-click "ShatterBreak was updated — keep
allowing?" prompt). No paid Apple Developer account or Apple secrets are needed;
the build is still un-notarized, so the quarantine step (see the README) is
unchanged.

**One-time setup.** In *Keychain Access > Certificate Assistant > Create a
Certificate…* create a certificate named `ShatterBreak Self-Signed`, with
*Identity Type: Self Signed Root* and *Certificate Type: Code Signing*. Keep it in
your login keychain and never delete or recreate it — that would change the DR and
drop the grant. Back it up by exporting a password-protected `.p12`.

**Archiving in Xcode signs automatically.** The scheme's *Archive* action has a
post-action that runs `Scripts/sign-release.sh` on the archived app, so *Product >
Archive* re-signs it with the stable identity for you. If the cert isn't present
(e.g. on CI, or before the one-time setup) the post-action is a no-op and the
archive still succeeds. Two caveats:

* Xcode ignores a post-action's exit status, so it is best-effort — verify with the
  command below.
* The Organizer's *Distribute App* re-signs and would replace the stable
  signature, so take the `.app` straight from the `.xcarchive`
  (*Products/Applications*) or use *Distribute App > Custom > Copy App*.

**Or sign a build manually** (e.g. the CI release zip, which is only ad-hoc signed):

```bash
Scripts/sign-release.sh path/to/ShatterBreak.app
```

Override the identity with `SIGN_IDENTITY=…` if you named the cert differently;
`SIGN_IDENTITY=-` falls back to ad-hoc signing (not update-stable). Confirm the
result is leaf-anchored (not `cdhash`):

```bash
codesign -d --requirements - path/to/ShatterBreak.app
# designated => identifier "dev.lipovoy.shatterbreak" and certificate leaf = H"…"
```
