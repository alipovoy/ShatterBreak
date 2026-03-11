import SwiftUI
import Combine

@MainActor
@Observable
final class TimerState {
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

    var isRunning = false
    var isPaused = false
    var isResting = false
    var hasPostponeBeenUsedThisCycle = false
    var timeRemaining: TimeInterval = 0

    /// When the user has chosen "manual" start mode and a rest has completed,
    /// the timer will not immediately begin a new work session. Instead we
    /// sit in a waiting state until the user presses the "I'm back" button.
    /// While this flag is true the timer is idle and no countdown occurs.
    var awaitingReturn = false

    var canPostpone: Bool {
        isResting && !hasPostponeBeenUsedThisCycle && !isInPostponedWork
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
        (isRunning || isPaused) && !isResting && !awaitingReturn
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

    private var isInPostponedWork = false
    private var savedRestRemaining: TimeInterval?
    private var timerTask: Task<Void, Never>?
    private var sleepObserverTasks = [Task<Void, Never>]()
    private let overlayManager: any OverlayManaging
    private var restStartedAt: Date?
    private var isSystemAsleep = false
    private var wasAutoPausedBySystem = false

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
        if isResting || awaitingReturn {
            overlayManager.dismissOverlays()
        }

        // leaving the waiting state if we were there.
        awaitingReturn = false

        timeRemaining = workDurationSecs
        isRunning = true
        isPaused = false
        wasAutoPausedBySystem = false
        runTimer()
    }

    func pause() {
        if isResting {
            timerTask?.cancel()
            restStartedAt = nil
            isResting = false
            overlayManager.dismissOverlays()
            start()
        } else {
            isPaused = true
            timerTask?.cancel()
        }
    }

    func resume() {
        isPaused = false
        runTimer()
    }

    func stop() {
        timerTask?.cancel()
        isRunning = false
        isPaused = false
        isResting = false
        isInPostponedWork = false
        wasAutoPausedBySystem = false
        awaitingReturn = false
        timeRemaining = 0
        restStartedAt = nil
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlayManager.dismissOverlays()
    }

    func postpone() {
        guard isResting && !hasPostponeBeenUsedThisCycle && !isInPostponedWork else { return }

        savedRestRemaining = timeRemaining
        isInPostponedWork = true
        hasPostponeBeenUsedThisCycle = true
        isResting = false
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
        if awaitingReturn {
            return
        }

        if isInPostponedWork {
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                resumeRest()
            }
        } else if isResting, let anchor = restStartedAt {
            timeRemaining = max(0, restDurationSecs - Date().timeIntervalSince(anchor))

            if timeRemaining <= 0 && !isSystemAsleep {
                timerTask?.cancel()
                restStartedAt = nil
                // we finished a rest period; decide whether we should kick
                // straight into work or wait for the user to return.
                if autoStartWorkTimer {
                    isResting = false
                    overlayManager.dismissOverlays()
                    start()
                } else {
                    // manual mode – remain on screen and show the "I'm back"
                    // button. The timer is no longer active until the user
                    // confirms their return; this keeps isRunning false so
                    // UI/tests treat the app as idle.
                    isResting = false
                    isRunning = false
                    awaitingReturn = true
                    timeRemaining = 0
                    // leave overlays visible
                }
            }
        } else {
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                triggerRestPhase()
            }
        }
    }

    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }

        isInPostponedWork = false
        isResting = true
        timeRemaining = saved

        let elapsed = restDurationSecs - saved
        restStartedAt = Date().addingTimeInterval(-elapsed)

        savedRestRemaining = nil
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    private func triggerRestPhase() {
        isResting = true
        isInPostponedWork = false
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
        guard isRunning && !isPaused && !isResting else { return }
        pause()
        wasAutoPausedBySystem = true
    }

    private func handleWake() {
        isSystemAsleep = false

        if isResting, let anchor = restStartedAt {
            let elapsed = Date().timeIntervalSince(anchor)
            // only treat the rest as finished if the countdown is actually
            // zero or less; the elapsed check alone proved unreliable in
            // unit tests where timing is imprecise.
            if elapsed >= restDurationSecs && timeRemaining <= 0 {
                timerTask?.cancel()
                restStartedAt = nil
                isResting = false
                isRunning = false
                overlayManager.dismissOverlays()
            }
        } else if wasAutoPausedBySystem {
            wasAutoPausedBySystem = false
            resume()
        }
    }
}
