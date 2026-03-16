# ShatterBreak Product Requirements and Technical Blueprint

## 1. Product Goal
ShatterBreak must be a native, sandboxed macOS menu bar utility that enforces alternating focus and rest periods. The application must interrupt the user with fullscreen overlays when a focus session ends, display a rest countdown, and provide a controlled set of options for continuing, postponing, or completing the break.

The document defines expected behavior and approved implementation direction. It may be used by both human developers and AI agents as the development blueprint for the application.

## 2. Platform and Technical Direction
* The application must target macOS 15.0 or later.
* The application must be implemented as a native macOS app.
* The primary user interface must be built with SwiftUI.
* The menu bar experience must be built around `MenuBarExtra`.
* Shared mutable application state must be modeled using Observation-based state, preferably `@Observable` types isolated to `@MainActor`.
* AppKit may be used where platform integration requires it, including:
    * borderless overlay windows
    * sound playback
    * system sleep and wake notifications
* ScreenCaptureKit may be used to capture screenshots for the shatter effect.
* The application must remain sandbox-compatible.
* The application must declare `NSScreenCaptureUsageDescription`.

## 3. Primary User Experience Requirements
### 3.1 Menu Bar Experience
* The application must present itself primarily through a menu bar extra.
* The menu bar extra should use a timer-related symbol such as `app.badge.clock`.
* The menu bar popover must expose the core application controls.

### 3.2 Menu Bar States
#### Inactive state
When the timer is inactive, the menu bar UI must provide:
* a `Start Focus` action
* a `Work Duration` control
* a `Rest Duration` control
* a `Preferences` action
* a `Quit` action

#### Active or paused state
When a timer is active or paused, the menu bar UI must provide:
* a prominent countdown display
* a `Pause` action during running work and postponed work
* a `Skip Rest` action during rest
* a `Resume` action when the timer is paused
* a `Stop` action

#### Duration editing rules
* Duration controls must be editable only when the application is inactive.
* Duration controls must be locked in every non-idle state, including:
    * running
    * paused
    * resting
    * postponed work
    * waiting for manual return

### 3.3 Optional Menu Bar Time Display
* The application must support an option to show the remaining time next to the menu bar icon.
* When enabled, the menu bar timer must be visible during:
    * running work
    * paused work
    * postponed work
* The menu bar timer must not be shown during:
    * rest
    * manual waiting-for-return state

## 4. Preferences Requirements
The Preferences window must be accessible from:
* the menu bar popover
* `Cmd+,`

The Preferences window must allow the user to configure:
* whether break sound playback is enabled
* whether the visual break effect is `Shatter` or `Overlay`
* whether `Soft Overlay` is enabled
* whether postponing is allowed
* whether work must restart automatically after a break or wait for manual confirmation
* whether the remaining time must be shown in the menu bar

### 4.1 Preference Defaults
* New installations must default to soft overlay mode.
* If the `softOverlay` preference is unset, the application must treat it as enabled.

### 4.2 Permission Messaging
* If the user selects the `Shatter` effect without screen recording permission, the application must warn the user inside Preferences.
* The Preferences window must provide a direct action for opening System Settings to the correct privacy area.

## 5. Timer and State Machine Requirements
The timer system must support the following modes:
* `idle`
* `running`
* `paused`
* `resting`
* `postponedWork`
* `awaitingReturn`

### 5.1 Focus and Rest Flow
* Starting focus must begin the work timer.
* When the work timer expires, the application must enter the rest phase.
* When the rest timer expires:
    * in automatic mode, the application must dismiss overlays and start a new work timer
    * in manual mode, the application must keep the overlay visible and wait for the user to confirm return

### 5.2 Pause Semantics
* `Pause` must freeze running work and postponed work.
* `Resume` must continue the same work phase that was paused.
* `Pause` and `Resume` do not need to apply to the resting phase.
* `Stop` must clear the active timer, dismiss overlays, and reset cycle-specific state.

### 5.3 Rest Skip Behavior
* During the resting phase, the primary menu bar action must be `Skip Rest`.
* `Skip Rest` must immediately dismiss the active break overlay.
* `Skip Rest` must cancel the remaining rest time.
* `Skip Rest` must start a fresh work timer.

## 6. Break Overlay Requirements
### 6.1 Overlay Creation
* When a break begins, the application must create fullscreen borderless overlay windows for all connected displays.
* The overlay windows must support safe teardown and repeated presentation across cycles.

### 6.2 Overlay Level Rules
* In soft overlay mode, overlay windows must remain below the menu bar so the menu bar extra stays reachable.
* In hard overlay mode, overlay windows must cover the menu bar.
* In hard overlay mode, in-app pause controls may become unreachable.
* Quitting the application must remain possible in hard overlay mode.

### 6.3 Visual Effects
* The application must support two break visuals:
    * `Shatter`
    * `Overlay`
* If the selected effect is `Shatter` and permission is available, the application should:
    * present overlay windows immediately
    * capture screenshots for the active displays without capturing the application's own overlay windows
    * avoid showing the dark fallback overlay as a temporary loading state while screenshot capture is pending
    * begin the shake/shatter intro only after capture results are available for the current break session
    * start the shatter intro for all active displays in sync
    * optionally play a glass sound
* If the selected effect is `Overlay`, the application must display a dark overlay without screenshot capture.

### 6.4 Fallback Behavior
* If screen recording permission is unavailable, screenshot-based background capture must be disabled, but the break flow must continue.
* If ScreenCaptureKit fails to enumerate displays or capture one or more screenshots, the application must fall back gracefully instead of cancelling the break flow.
* In shatter mode, a display that does not receive a captured screenshot may fall back to a dark background on that display while still completing the shatter sequence.
* Per-display capture failures may fall back on a display-by-display basis.

### 6.5 Overlay Content
During a break overlay, the application must display:
* the remaining rest time
* a `Postpone` action only when postponing is enabled and still available for the current cycle
* an `I'm back` action when the application is waiting for manual return
* In `Shatter` mode, the break controls and countdown may remain hidden until the shatter intro completes.

## 7. Postpone Requirements
* Postponing must be optional and user-configurable.
* Postpone must be available only during rest.
* Postpone must be allowed once per work/rest cycle.
* When postpone is used:
    * the remaining rest duration must be saved
    * the application must enter postponed work
    * the overlay must be dismissed
* When postponed work expires:
    * the application must resume the saved remainder of the interrupted rest period
* The postpone duration may be implemented as a fixed value. The current blueprint allows a 60-second postpone duration.

## 8. Sleep, Wake, and Lifecycle Requirements
* The application must observe system sleep and wake notifications.
* The application must observe display sleep and wake notifications.
* If the system sleeps during running work or postponed work:
    * the timer must auto-pause
    * the timer must auto-resume on wake only if the system caused the pause
* Rest should not be transformed into a paused state during sleep.
* When waking from sleep during rest:
    * if the rest timer expired while the system was asleep, the application must dismiss overlays and return to idle
    * if the rest timer did not expire while the system was asleep, the application must continue the remaining break time
* The application must refresh permission state when the app becomes active.

## 9. Screen Capture Permission Requirements
* The application must ask for screen capture permission at first launch.
* To indicate that the initial permission request has already been attempted, a first-launch flag may be used.
* The application must continue working even if the permission is denied.
* Denied permission must disable screenshot-based shatter capture, but must not disable the break flow itself.

## 10. Persistence Requirements
The application must persist the following user preferences:
* `workDurationSecs`
* `restDurationSecs`
* `playSound`
* `effectType`
* `softOverlay`
* `allowPostpone`
* `showTimerInMenuBar`
* `workStartMode`

The application may also persist:
* a first-launch flag used to control initial permission request behavior

## 11. Quality and Testing Requirements
The application must include automated tests for the core timer and overlay logic.

The test suite must validate:
* timer state transitions
* pause and resume behavior
* skip-rest behavior during the resting phase
* stop behavior
* postpone eligibility rules
* postponed-work resumption into the saved rest time
* overlay lifecycle behavior
* shatter presentation-state behavior, including fallback when a screenshot is unavailable
* sleep and wake edge cases
* permission manager behavior
* duration parsing and slider snapping behavior
* manual-return behavior after break completion

## 12. Implementation Guidance
The following implementation choices are approved by this blueprint:
* SwiftUI for app structure and primary views
* AppKit windows for fullscreen overlay presentation
* ScreenCaptureKit for screenshot-based shatter visuals
* `UserDefaults` and `@AppStorage` for local preference persistence
* Observation-based state with a central timer state model
* Excluding the current application from ScreenCaptureKit capture filters to avoid recursive overlay capture

Alternative implementations may be used only if they preserve the product behavior defined above.
