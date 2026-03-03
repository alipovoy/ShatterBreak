# Product Requirements Document: "ShatterBreak" (macOS Menubar App)

## 1. Overview
A native, sandboxed macOS menubar utility designed to enforce work breaks without permanently locking the user out. It visually obscures the screen when work time is over, displaying a mandatory resting timer. It features a rich popover UI, screen capture permission handling, a separate Preferences window, and intelligent system sleep detection.

## 2. Technical Stack
* **Platform:** macOS 14.0+ (Native)
* **Frameworks:** SwiftUI (UI Popover, Canvas, Windows), AppKit (Window management, `NSSound`, `NSWorkspace`), `ScreenCaptureKit` (Screen Capture), Combine/Observation (State)
* **Security:** App Sandbox enabled. Requires `NSScreenCaptureUsageDescription` in `Info.plist`.

## 3. UI/UX Requirements
### 3.1 Menubar Popover (`.window` style)
* **Icon:** Standard status bar icon (e.g., `app.badge.clock`).
* **State: Inactive (Ready)**
    * `Start Focus` action button.
    * `Work Duration` configuration: Custom `DurationSliderView` showing time in minutes/seconds dynamically. Clamped between 5 and 7200 seconds.
    * `Rest Duration` configuration: Custom `DurationSliderView` showing time in minutes/seconds dynamically. Clamped between 5 and 3600 seconds.
    * `Preferences` action (gear icon).
    * `Quit` action.
* **State: Active**
    * `Remaining Time` text (MM:SS) prominently displayed.
    * `Pause` action.
    * `Stop` action.
    * Sliders are disabled.
* **State: Paused**
    * `Resume` action (replaces Pause).
    * `Stop` action.

### 3.2 Preferences Window
* Opened via Menubar Popover (gear icon) or `Cmd+,`.
* Configures global app settings:
    * `Play Sound` (Toggle): Whether to play sound during break initiation.
    * `Effect Type` (Radio group): "Shatter" or "Overlay" effect styles.
* Displays permission warnings if "Shatter" is selected but Screen Recording permission is denied, providing a link to System Settings.

### 3.3 Notification Sequence (The "Break")
1.  **Permission & Effect Type Check:** If "Shatter" effect is chosen, `ScreenCaptureManager` evaluates `CGPreflightScreenCaptureAccess()`.
2.  **Overlay Creation:** Spawn borderless `NSWindow` instances on all monitors.
    * *Crucial Leveling:* Window level is `NSWindow.Level.mainMenu.rawValue - 1`. This blocks clicks to desktop apps but leaves the macOS menubar (and the ShatterBreak icon) clickable for emergency stops.
    * *Safe Teardown:* Windows have `isReleasedWhenClosed = false`.
3.  **Animation/Visual Phase:**
    * *If "Shatter" effect & permitted:* Display screenshot, apply tremble, play sound (if enabled), and render procedural jagged cracks (`CrackedGlassView`).
    * *If "Overlay" effect or "Shatter" denied:* Display a semi-transparent black overlay.
4.  **Timer Phase:**
    * Display the countdown timer in the center of the screen.
5.  **Completion:** Safely dismiss all overlays, detach SwiftUI views, and automatically restart the Work Timer.

## 4. System Integration
* **Sleep Detection:** Observes `NSWorkspace` notifications for system and display sleep/wake events.
* **Auto-Pause/Resume:** Automatically pauses the active timer when the system or display goes to sleep. Automatically resumes the timer upon waking *only* if the system was responsible for pausing it.
* **Permissions Monitoring:** Observes `didBecomeActiveNotification` to refresh Screen Recording permission status after users visit System Settings.

## 5. Data Storage
* Timer configurations (`workDurationSecs`, `restDurationSecs`), `playSound`, and `effectType` are stored persistently using `UserDefaults` via SwiftUI `@AppStorage`.
