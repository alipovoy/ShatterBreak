# Product Requirements Document: "ShatterBreak" (macOS Menubar App)

## 1. Overview
A native, sandboxed macOS menubar utility designed to enforce work breaks without permanently locking the user out. It visually "shatters" the screen when work time is over, displaying a mandatory resting timer over the cracked desktop. It features a rich popover UI and intelligent system sleep detection.

## 2. Technical Stack
* **Platform:** macOS 13.0+ (Native)
* **Frameworks:** SwiftUI (UI Popover, Canvas), AppKit (Window management, `NSSound`, `NSWorkspace`), `ScreenCaptureKit` (Screen Capture), Combine/Observation (State)
* **Security:** App Sandbox enabled. Requires `NSScreenCaptureUsageDescription` in `Info.plist`.

## 3. UI/UX Requirements
### 3.1 Menubar Popover (`.window` style)
* **Icon:** Standard status bar icon (e.g., `timer`).
* **State: Inactive (Ready)**
    * `Start Focus` action button.
    * `Work Duration` configuration: Logarithmic slider + Numeric text field. Clamped between 5 and 7200 seconds.
    * `Rest Duration` configuration: Logarithmic slider + Numeric text field. Clamped between 5 and 3600 seconds.
    * *Validation:* Inputs are validated and clamped when the user presses `Return` or when the text field loses focus (`@FocusState`).
    * `Quit` action.
* **State: Active**
    * `Remaining Time` text (MM:SS) prominently displayed.
    * `Pause` action.
    * `Stop` action.
    * Sliders and text fields are disabled.
* **State: Paused**
    * `Resume` action (replaces Pause).
    * `Stop` action.

### 3.2 Notification Sequence (The "Break")
1.  **Permission & Capture:** Evaluate `CGPreflightScreenCaptureAccess()`. Use `ScreenCaptureKit` asynchronously on a background task to capture pixel data for all connected displays.
2.  **Overlay Creation:** Spawn borderless `NSWindow` instances on all monitors. 
    * *Crucial Leveling:* Window level is `NSWindow.Level.mainMenu.rawValue - 1`. This blocks clicks to desktop apps but leaves the macOS menubar (and the ShatterBreak icon) clickable for emergency stops.
    * *Safe Teardown:* Windows have `isReleasedWhenClosed = false` and use SwiftUI `.task` lifecycles to prevent memory access crashes if stopped prematurely.
3.  **Animation Phase 1 (0-2s):**
    * *If permitted:* Display static screenshot.
    * *If denied:* Display a semi-transparent black overlay.
4.  **Animation Phase 2 (2-4s):**
    * *If permitted:* Apply a horizontal/vertical tremble (shake) effect.
    * *If denied:* Tremble is skipped.
5.  **Animation Phase 3 (4s+):** * Play built-in macOS `"Glass"` system sound via `NSSound`.
    * Render procedural jagged cracks using a SwiftUI `Canvas` (`CrackedGlassView`) overlay.
    * Display the countdown timer in the center of the screen.
6.  **Completion:** Safely dismiss all overlays, detach SwiftUI views, and automatically restart the Work Timer.

## 4. System Integration
* **Sleep Detection:** Observes `NSWorkspace` notifications for system and display sleep/wake events.
* **Auto-Pause/Resume:** Automatically pauses the active timer when the system or display goes to sleep. Automatically resumes the timer upon waking *only* if the system was responsible for pausing it.

## 5. Data Storage
* Timer configurations (Work duration seconds, Rest duration seconds) stored persistently using `UserDefaults` via SwiftUI `@AppStorage`.
