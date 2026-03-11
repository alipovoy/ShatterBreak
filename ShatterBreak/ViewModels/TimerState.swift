import SwiftUI
import Combine

@MainActor
@Observable
final class TimerState {
    enum Mode {
        case idle           // nothing active
        case running        // counting down a work period
        case paused         // work was paused by user or system
        case resting        // currently in a rest interval
        case postponedWork  // work running during a postponed rest
        case awaitingReturn // manual‑start mode, waiting for user
    }

    /// Represents the sole active state of the timer. All previous
    /// boolean flags have been consolidated into this enum. Computed
    /// properties below provide compatibility for existing callers.
    var mode: Mode = .idle

    var workDurationSecs: Double {
        didSet {
            UserDefaults.standard.set(workDurationSecs, forKey: "workDurationSecs")
        }
    }

    var restDurationSecs: Double {
        didSet {
            UserDefaults.standard.set(restDurationSecs, forKey: "restDurationSecs")
        }
    }

    var postponeDurationSecs: Double = 60

    // these helpers mirror the old boolean fields so views/tests can still
    // refer to them without major rewrites. They are read‑only; tests
    // should now set `mode` directly when simulating state.
    var isRunning: Bool {
        mode == .running || mode == .resting || mode == .postponedWork
    }
    var isPaused: Bool {
        mode == .paused
    }
    var isResting: Bool {
        mode == .resting
    }
    var awaitingReturn: Bool {
        mode == .awaitingReturn
    }

    /// Internal computed flag used to determine when we're in postponed work.
    private var isInPostponedWork: Bool { mode == .postponedWork }

    var hasPostponeBeenUsedThisCycle = false
    var timeRemaining: TimeInterval = 0

    var canPostpone: Bool {
        mode == .resting && !hasPostponeBeenUsedThisCycle && !isInPostponedWork
    }

    /// A human-readable representation of the remaining time suitable for display
    /// in the menubar or other compact UI. When no timer is active an empty string
    /// is returned.
    /// `true` when the menubar label should show a timer value. This
    /// isolates the decision logic from presentation, allowing callers to
    /// consult the state directly rather than interpret an empty string.
    var shouldShowTimeInMenuBar: Bool {
        // don't display during rest because the transparent screenshot overlay
        // can obscure the text, and avoid showing anything when the timer is
        // idle or waiting for the user to return.
        switch mode {
        case .running, .paused, .postponedWork:
            return true
        default:
            return false
        }
    }

    /// A formatted string for the remaining time. This property no longer
    /// encodes visibility decisions; callers may format regardless of whether
    /// it will be shown.
    var formattedTimeRemaining: String {
        TimerState.format(timeInterval: timeRemaining)
    }

    /// Helper formatter used by both the state and UI components.
    nonisolated static func format(timeInterval interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        let minutesPadded = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        let secondsPadded = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutesPadded):\(secondsPadded)"
    }

    private var savedRestRemaining: TimeInterval?
    private var timerTask: Task<Void, Never>?
    private var sleepObserverTasks = [Task<Void, Never>]()
    private let overlayManager: any OverlayManaging
    private var restStartedAt: Date?
    private var isSystemAsleep = false
    private var wasAutoPausedBySystem = false
    private var previousModeBeforeSleep: Mode?

    /// Helper to read the work‑start preference from UserDefaults. This is
    /// intentionally computed each time so tests can mutate defaults mid‑run.
    private var autoStartWorkTimer: Bool {
        let raw = UserDefaults.standard.string(forKey: "workStartMode") ?? WorkStartMode.automatic.rawValue
        return WorkStartMode(rawValue: raw) == .automatic
    }

    init(overlayManager: any OverlayManaging, postponeDurationSecs: Double = 60) {
        self.overlayManager = overlayManager
        self.workDurationSecs = UserDefaults.standard.double(forKey: "workDurationSecs")
        self.restDurationSecs = UserDefaults.standard.double(forKey: "restDurationSecs")
        self.postponeDurationSecs = postponeDurationSecs

        // Set defaults if not previously saved
        if self.workDurationSecs == 0 { self.workDurationSecs = 1500 }
        if self.restDurationSecs == 0 { self.restDurationSecs = 300 }

        setupSleepObservers()
    }

    init(postponeDurationSecs: Double = 60) {
        self.overlayManager = OverlayManager()
        self.workDurationSecs = UserDefaults.standard.double(forKey: "workDurationSecs")
        self.restDurationSecs = UserDefaults.standard.double(forKey: "restDurationSecs")
        self.postponeDurationSecs = postponeDurationSecs

        if self.workDurationSecs == 0 { self.workDurationSecs = 1500 }
        if self.restDurationSecs == 0 { self.restDurationSecs = 300 }

        setupSleepObservers()
    }

    func start() {
        // only clear overlays if we were resting or waiting; the menu UI will
        // already be correct in the idle case and the spy will not be tripped.
        if mode == .resting || mode == .awaitingReturn {
            overlayManager.dismissOverlays()
        }

        // kick off a fresh work interval
        mode = .running
        timeRemaining = workDurationSecs
        wasAutoPausedBySystem = false
        runTimer()
    }

    func pause() {
        if mode == .resting || mode == .postponedWork {
            timerTask?.cancel()
            restStartedAt = nil
            // exit rest/postponed work and immediately start new work period
            overlayManager.dismissOverlays()
            start()
        } else {
            mode = .paused
            timerTask?.cancel()
        }
    }

    func resume() {
        // resuming always goes back to running; if we were paused during
        // postponed work that's fine – mode will be reset below.
        mode = .running
        runTimer()
    }

    func stop() {
        timerTask?.cancel()
        mode = .idle
        wasAutoPausedBySystem = false
        timeRemaining = 0
        restStartedAt = nil
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlayManager.dismissOverlays()
    }

    func postpone() {
        guard mode == .resting && !hasPostponeBeenUsedThisCycle && !isInPostponedWork else { return }

        savedRestRemaining = timeRemaining
        mode = .postponedWork
        hasPostponeBeenUsedThisCycle = true
        timeRemaining = postponeDurationSecs
        overlayManager.dismissOverlays()
    }

    private func runTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }

    private func tick() {
        // if waiting for the user we shouldn’t count down or transition;
        // just idle until start() is invoked.
        if mode == .awaitingReturn {
            return
        }

        if mode == .postponedWork {
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                resumeRest()
            }
        } else if mode == .resting, let anchor = restStartedAt {
            timeRemaining = max(0, restDurationSecs - Date().timeIntervalSince(anchor))

            if timeRemaining <= 0 && !isSystemAsleep {
                timerTask?.cancel()
                restStartedAt = nil
                // we finished a rest period; decide whether we should kick
                // straight into work or wait for the user to return.
                if autoStartWorkTimer {
                    mode = .running
                    overlayManager.dismissOverlays()
                    start()
                } else {
                    // manual mode – remain on screen and show the "I'm back"
                    // button. The timer is no longer active until the user
                    // confirms their return; this keeps `mode` at awaitingReturn
                    // so UI/tests treat the app as idle.
                    mode = .awaitingReturn
                    timeRemaining = 0
                    // leave overlays visible
                }
            }
        } else {
            // running work (or paused state shouldn't have a timer running at
            // all because we cancel when entering paused)
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                triggerRestPhase()
            }
        }
    }

    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }

        mode = .resting
        timeRemaining = saved

        let elapsed = restDurationSecs - saved
        restStartedAt = Date().addingTimeInterval(-elapsed)

        savedRestRemaining = nil
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    private func triggerRestPhase() {
        mode = .resting
        hasPostponeBeenUsedThisCycle = false
        savedRestRemaining = nil
        restStartedAt = Date()
        timeRemaining = restDurationSecs
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    private func setupSleepObservers() {
        let notifications: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]

        for name in notifications {
            sleepObserverTasks.append(Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: name) {
                    self?.handleNotification(name)
                }
            })
        }
    }

    private func handleNotification(_ name: NSNotification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification,
             NSWorkspace.screensDidSleepNotification:
            handleSleep()
        case NSWorkspace.didWakeNotification,
             NSWorkspace.screensDidWakeNotification:
            handleWake()
        default: break
        }
    }

    private func handleSleep() {
        isSystemAsleep = true
        // only auto‑pause if we were actively running (including postponed work)
        guard mode == .running || mode == .postponedWork else { return }
        // For postponed work, just pause like normal work; don't trigger new cycle
        mode = .paused
        timerTask?.cancel()
        wasAutoPausedBySystem = true
    }

    private func handleWake() {
        isSystemAsleep = false

        if mode == .resting, let anchor = restStartedAt {
            let elapsed = Date().timeIntervalSince(anchor)
            // only treat the rest as finished if the countdown is actually
            // zero or less; the elapsed check alone proved unreliable in
            // unit tests where timing is imprecise.
            if elapsed >= restDurationSecs && timeRemaining <= 0 {
                timerTask?.cancel()
                restStartedAt = nil
                // return to idle; overlay should already be visible but we
                // don't want the timer running.
                mode = .idle
                overlayManager.dismissOverlays()
            }
        } else if wasAutoPausedBySystem {
            wasAutoPausedBySystem = false
            // If we were in postponed work before sleep, resume it; otherwise resume normally
            if previousModeBeforeSleep == .postponedWork {
                mode = .postponedWork
            } else {
                mode = .running
            }
            runTimer()
        }
        previousModeBeforeSleep = nil
    }
}
