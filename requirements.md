# ShatterBreak Current Implementation Blueprint

This document mirrors the current project state so a human or LLM can understand
and, if needed, recreate the app. Future improvements and known gaps are tracked in
`.env/TODO.md`, not described here as completed behavior.

## 1. Product Shape
ShatterBreak is a native, sandboxed macOS menu bar utility for alternating focus and
rest periods. It lives primarily in the menu bar, starts a work countdown, then shows
fullscreen break overlays on all connected displays when work time expires.

During a break, the overlay can show a rest countdown, optionally allow one
postpone, and either automatically restart work after the break or wait for the user
to confirm they are back.

## 2. Platform And Project Configuration
* The project is defined by `project.yml` and generated locally with XcodeGen.
* The app target is a native macOS application with deployment target `15.0`.
* The project currently sets `SWIFT_VERSION` to `6.0`.
* The app uses SwiftUI for app structure and primary UI, with AppKit where macOS
  integration requires it.
* The app is configured as a menu bar utility with generated Info.plist settings,
  including `LSUIElement`.
* The app enables the hardened runtime and app sandbox through build settings
  (`ENABLE_HARDENED_RUNTIME`, `ENABLE_APP_SANDBOX`).
* The entitlements file (`ShatterBreak.entitlements`) declares only
  `com.apple.security.app-sandbox`. Screen recording for the shatter effect relies on
  the system TCC permission grant rather than a dedicated capture entitlement.

AppKit is currently used for:
* menu/window visibility tracking in the menu bar window
* borderless overlay windows
* screen, workspace, and application notifications
* sound playback
* opening System Settings for screen recording permission

ScreenCaptureKit is used for screenshot-based shatter backgrounds when permission
is available.

## 3. App Structure And UI
`ShatterBreakApp` owns the main `TimerState` and shared
`ScreenCapturePermissionManager` using SwiftUI `@State`. It exposes:
* a `MenuBarExtra` with `.window` style
* a Preferences window with id `preferences`
* an `@Entry` environment value for permissions

The menu bar label always shows the `app.badge.clock` symbol. When the user enables
menu bar timer text, it also shows the remaining time during running work, paused
work, and postponed work. It does not show the timer text during rest or manual
waiting-for-return.

`MenuView` provides the active control surface:
* idle state: `Start Focus`, work/rest duration controls, Preferences, Quit
* running work or postponed work: Pause and Stop
* paused: Resume and Stop
* resting: Skip Rest and Stop

Duration controls are disabled outside the idle state. `DurationSliderView` supports
slider editing plus manual text input parsed by the `DurationFormat` helpers.

`PreferencesView` stores settings with `@AppStorage` and currently exposes:
* `Play Sound`
* `Soft Overlay (allows menu bar access)`
* `Allow Postpone`
* `Effect Type`: `Shatter` or `Overlay`
* `Start work after break ends`: `Automatic` or `Manual`
* `Show timer in menu bar`

If the user selects `Shatter` without screen recording permission, Preferences shows
an alert. If permission is denied, it also shows an inline warning with an action that
opens System Settings.

## 4. Timer State Machine
`TimerState` is an `@MainActor @Observable` class. It is the central state machine
for focus/rest cycles and supports these modes:
* `idle`
* `running`
* `paused`
* `resting`
* `postponedWork`
* `awaitingReturn`

Work and rest durations are persisted in `UserDefaults` under `PreferenceKeys`.
Missing or zero stored duration values fall back to defaults of 1500 seconds for work
and 300 seconds for rest.

The active countdown is represented by an active deadline plus frozen remaining time.
The production timer uses a `Task` with `Task.sleep(for:tolerance:)`; tests can inject
`ManualTimerTickSource` for deterministic manual time advancement.

Focus/rest behavior:
* `start()` starts a work countdown and dismisses overlays if called from rest or
  awaiting-return.
* Work expiry enters rest, shows overlays, and starts the rest countdown.
* Rest expiry in automatic mode dismisses overlays and starts a new work countdown.
* Rest expiry in manual mode keeps the overlay visible and enters `awaitingReturn`.
* `pause()` freezes running work or postponed work.
* During rest, `pause()` is used as Skip Rest: it clears the rest countdown,
  dismisses overlays, and starts work.
* `resume()` continues the phase that was paused.
* `stop()` clears countdown state, returns to idle, dismisses overlays, and resets
  cycle-specific postpone state.

## 5. Postpone Behavior
Postpone is optional and controlled by the `allowPostpone` preference. The overlay
shows a Postpone button only while:
* the timer is resting
* postpone is enabled
* postpone has not already been used in the current cycle

Using postpone:
* saves the current remaining rest time
* dismisses overlays
* enters `postponedWork`
* starts a fixed postponed-work countdown
* marks postpone as used for the current cycle

When postponed work expires, the app resumes rest using the saved remaining rest
time and shows overlays again. The postpone-used flag stays set until a fresh rest
cycle begins or the timer is stopped.

## 6. Overlay Presentation
`OverlayManager` creates one borderless `NSWindow` per connected `NSScreen` when a
break begins. It keeps windows and per-display `OverlayPresentationState` instances
keyed by `CGDirectDisplayID`.

Overlay windows:
* use the screen frame as their content rect
* are non-opaque with a clear background
* can join all spaces and support fullscreen auxiliary presentation
* are safely torn down by clearing `contentView`, ordering out, and removing stored
  state

Soft overlay mode is enabled by default when the preference is unset. In soft mode,
overlay windows sit just below the menu bar level. In hard overlay mode, they use
`.screenSaver` level and can cover the menu bar.

The app supports two effect types:
* `Overlay`: a dark overlay without screenshot capture
* `Shatter`: a screenshot-backed shatter sequence when screen recording permission
  and capture succeed

For shatter mode, overlay windows are presented immediately. If screen recording
permission is available, `OverlayManager` captures screenshots asynchronously with
ScreenCaptureKit while excluding the current app from capture filters. The shatter
intro begins only when capture results return for the active session.

Fallback behavior:
* Without screen recording permission, shatter still progresses using dark fallback
  backgrounds.
* If display enumeration fails, the app falls back to no captured images.
* If capture fails for a display, that display falls back independently while the
  rest of the break flow continues.
* Stale capture results are ignored by checking the active session id.

`OverlayView` renders the selected background, optional crack drawing, countdown, and
actions. In shatter mode, foreground break controls stay hidden until the shatter
intro finishes. If Reduce Motion is enabled, the shatter intro skips the shake delay
and transitions directly to the shattered phase.

## 7. Screen Capture Permission Flow
`ScreenCapturePermissionManager` is an `@MainActor @Observable` class. It wraps
screen capture permission checks through `ScreenCapturePermissionClient`.

Current behavior:
* A shared manager is used by default.
* On first launch, the app sets a launch flag and calls `CGRequestScreenCaptureAccess`.
* `refresh()` reports `.granted` when preflight access succeeds.
* If preflight fails before the first launch request, status is `.notDetermined`.
* If preflight fails after the first launch request, status is `.denied`.
* While permission remains unresolved, the manager observes app activation and
  refreshes status when the app becomes active.
* Once permission is granted, the app-active observer is removed.
* Opening System Settings uses the current privacy URL for screen recording.

Permission denial disables screenshot-backed capture, but it does not disable break
overlays or the rest timer flow.

## 8. Sleep And Wake Behavior
`TimerState` observes workspace sleep and wake notifications while countdowns are
active:
* `NSWorkspace.willSleepNotification`
* `NSWorkspace.screensDidSleepNotification`
* `NSWorkspace.didWakeNotification`
* `NSWorkspace.screensDidWakeNotification`

If the system or displays sleep during running work or postponed work, the timer
freezes, records the previous mode, enters `paused`, and marks the pause as
system-initiated. On wake, only system-initiated pauses resume automatically.

Rest is not converted into paused mode during sleep. When waking during rest:
* if the rest deadline elapsed while asleep, the app clears the countdown, dismisses
  overlays, returns to idle, and deactivates sleep observers
* if the rest deadline has not elapsed, rest continues with the existing remaining
  time

Observer tasks capture the model weakly and are cancelled during teardown.

## 9. Persistence
The app currently persists these values with `UserDefaults` / `@AppStorage`:
* `workDurationSecs`
* `restDurationSecs`
* `playSound`
* `effectType`
* `softOverlay`
* `allowPostpone`
* `showTimerInMenuBar`
* `workStartMode`
* `com.shatterbreak.hasLaunchedBefore`

`EffectType` and `WorkStartMode` are `RawRepresentable` enums with lowercase stored
raw values. Their initializers also accept older capitalized values for compatibility.

## 10. Tests
The project has a Swift Testing unit-test target, `ShatterBreakTests`, hosted by the
app target. Tests focus on behavior that is hard to verify by hand (and deliberately
omit tautological assertions over one-line computed properties). They cover:
* basic timer transitions, formatting, and manual-return mode
* sleep/wake behavior, including rest expiry while asleep and wake before expiry
* overlay lifecycle behavior
* postpone state transitions, pause/resume, stop, and saved rest time
* overlay presentation state, screenshot fallback, and Reduce Motion action
  resolution
* screen capture permission manager behavior
* duration parsing, formatting, and slider snapping (`DurationFormat`)

Tests use `TestEnvironment` to isolate `UserDefaults`, notification centers, and
manual timer ticks. `OverlayRecorder` provides an `OverlayPresenter` that records
overlay show/dismiss calls.

Known test-quality follow-ups, including tags, time limits, and richer expectation
messages, are tracked in `.env/TODO.md`.
