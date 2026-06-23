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

App versions follow [Semantic Versioning](https://semver.org) and are derived
from [Conventional Commits](https://www.conventionalcommits.org) at release
time. The version is decoupled from PR merges — it only changes when a release
is cut.

See [RELEASING.md](./RELEASING.md) for the full version scheme and the
release-cutting process.

## Running quarantined builds
macOS marks unsigned app as quarantined, remove the quarantine attribute before launching it:

```bash
xattr -dr com.apple.quarantine ShatterBreak.app
```

## Permissions that survive updates
The `Shatter` effect needs Screen Recording permission. macOS ties that grant to
the app's code-signing **Designated Requirement (DR)**. An ad-hoc signature
(`codesign --sign -`, what CI produces) has a DR equal to the binary's `cdhash`,
which changes on every build — so each new version looks like a different app and
you have to re-add it under *System Settings > Privacy & Security > Screen
Recording* after every update.

Signing with a **stable self-signed certificate that you create once and reuse**
gives a constant DR (`identifier "…" and certificate leaf = H"…"`), so the grant
carries over across updates (at most a one-click "ShatterBreak was updated — keep
allowing?" prompt). No paid Apple Developer account or Apple secrets are needed;
the build is still un-notarized, so the quarantine step above is unchanged.

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
