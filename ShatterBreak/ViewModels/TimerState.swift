import SwiftUI

/// Manages the timer state machine for work/rest cycles with postpone capability.
///
/// Countdown mechanics live in `Countdown` and sleep/wake observation in
/// `SleepWakeObserver`; this type owns the state machine that coordinates them.
@MainActor
@Observable
final class TimerState {
    // MARK: - Types

    /// Represents the current operational state of the timer.
    enum Mode: Equatable {
        case idle           // No active timer
        case running        // Counting down work period
        case paused         // Work paused (user or system initiated)
        case resting        // Counting down rest period
        case postponedWork  // Postponed rest, counting down work period
        case awaitingReturn // Manual mode: rest complete, waiting for user
    }

    // MARK: - Properties

    /// The current operational mode. All boolean state flags derive from this.
    var mode: Mode = .idle

    var workDurationSecs: Double {
        didSet { defaults.set(workDurationSecs, forKey: PreferenceKeys.workDurationSecs) }
    }

    var restDurationSecs: Double {
        didSet { defaults.set(restDurationSecs, forKey: PreferenceKeys.restDurationSecs) }
    }

    /// Whether postpone is available this cycle: only when resting and not yet used.
    var canPostpone: Bool {
        mode == .resting && !hasPostponeBeenUsedThisCycle
    }

    /// Whether the timer is actively counting down (work, rest, or postponed work).
    var isRunning: Bool {
        mode == .running || mode == .resting || mode == .postponedWork
    }

    var isPaused: Bool { mode == .paused }
    var isResting: Bool { mode == .resting }
    var awaitingReturn: Bool { mode == .awaitingReturn }
    var canEditDurations: Bool { mode == .idle }

    var hasPostponeBeenUsedThisCycle = false

    /// The remaining time at the tick source's current moment.
    var timeRemaining: TimeInterval {
        countdown.remaining(at: countdown.now)
    }

    var shouldShowTimeInMenuBar: Bool {
        switch mode {
        case .running, .paused, .postponedWork:
            return true
        default:
            return false
        }
    }

    var formattedTimeRemaining: String {
        formattedTimeRemaining(at: countdown.now)
    }

    // MARK: - Private State

    private var savedRestRemaining: TimeInterval?
    private var isSystemAsleep = false

    /// A test-supplied postpone delay that takes precedence over the live preference;
    /// `nil` in the app so the value is read from preferences. Read by the break-button
    /// extension in `TimerState+BreakButtons.swift`.
    let postponeDurationOverride: Double?

    /// The mode to restore when a user pause resumes; `nil` when not paused.
    private var modeBeforePause: Mode?

    /// The moment sleep/display-off began, used to measure how long the user was
    /// away on wake. `nil` while awake.
    private var sleptAt: Date?

    /// Internal (not `private`) so the break-button extension can read the clock.
    let countdown: Countdown
    private let sleepWakeObserver: SleepWakeObserver
    private let overlays: OverlayPresenter
    /// Internal (not `private`) so the break-button extension can read live preferences.
    let defaults: any KeyValueStore

    private var autoStartWorkTimer: Bool {
        (defaults.string(forKey: PreferenceKeys.workStartMode)
            .flatMap { WorkStartMode(rawValue: $0) } ?? PreferenceDefaults.workStartMode) == .automatic
    }

    // MARK: - Initialization

    init(
        overlays: OverlayPresenter,
        postponeDurationSecs: Double? = nil,
        defaults: any KeyValueStore = UserDefaults.standard,
        scheduler: (any CountdownScheduler)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.overlays = overlays
        self.postponeDurationOverride = postponeDurationSecs
        self.defaults = defaults
        self.countdown = Countdown(scheduler: scheduler ?? SystemCountdownScheduler())
        self.sleepWakeObserver = SleepWakeObserver(notificationCenter: workspaceNotificationCenter)
        self.workDurationSecs = Self.loadDuration(
            forKey: PreferenceKeys.workDurationSecs,
            defaultValue: PreferenceDefaults.workDurationSecs,
            defaults: defaults)
        self.restDurationSecs = Self.loadDuration(
            forKey: PreferenceKeys.restDurationSecs,
            defaultValue: PreferenceDefaults.restDurationSecs,
            defaults: defaults)
    }

    convenience init(
        postponeDurationSecs: Double? = nil,
        defaults: any KeyValueStore = UserDefaults.standard,
        scheduler: (any CountdownScheduler)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.init(
            overlays: .live(defaults: defaults),
            postponeDurationSecs: postponeDurationSecs,
            defaults: defaults,
            scheduler: scheduler,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    isolated deinit {
        countdown.clear()
        sleepWakeObserver.stopObserving()
    }

    private static func loadDuration(
        forKey key: String,
        defaultValue: Double,
        defaults: any KeyValueStore
    ) -> Double {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : defaultValue
    }

    // MARK: - User Actions

    func start() {
        if mode == .resting || mode == .awaitingReturn {
            overlays.dismiss()
        }

        mode = .running
        modeBeforePause = nil
        beginCountdown(for: workDurationSecs)
    }

    /// Starts a work session at launch when the user has opted in.
    ///
    /// Guarded to `.idle` so it only fires for a fresh launch and never disrupts an
    /// already-active cycle if invoked more than once.
    func autoStartIfEnabled() {
        let enabled = defaults.object(forKey: PreferenceKeys.autoStartOnLaunch) as? Bool
        guard mode == .idle, enabled ?? PreferenceDefaults.autoStartOnLaunch else { return }
        start()
    }

    func pause() {
        switch mode {
        case .running, .postponedWork:
            modeBeforePause = mode
            countdown.freeze()
            mode = .paused
        case .resting:
            // `start()` dismisses the overlays because `mode` is still `.resting`.
            countdown.clear()
            start()
        case .idle, .paused, .awaitingReturn:
            return
        }
    }

    func resume() {
        guard mode == .paused else { return }

        mode = modeBeforePause ?? .running
        modeBeforePause = nil
        resumeCountdown()
    }

    func stop() {
        resetToIdle()
    }

    func postpone() {
        guard mode == .resting && !hasPostponeBeenUsedThisCycle else { return }

        let remainingRest = timeRemaining
        countdown.freeze()
        savedRestRemaining = remainingRest
        mode = .postponedWork
        hasPostponeBeenUsedThisCycle = true
        overlays.dismiss()
        beginCountdown(for: postponeDurationSecs)
    }

    // MARK: - Timer Control

    func timeRemaining(at referenceDate: Date) -> TimeInterval {
        countdown.remaining(at: referenceDate)
    }

    func formattedTimeRemaining(at referenceDate: Date) -> String {
        Self.format(timeInterval: timeRemaining(at: referenceDate))
    }

    private func beginCountdown(for duration: TimeInterval) {
        sleepWakeObserver.startObserving(
            onSleep: { [weak self] in self?.handleSleep() },
            onWake: { [weak self] in self?.handleWake() }
        )
        countdown.begin(for: duration) { [weak self] in
            self?.handleCountdownExpiryIfNeeded()
        }
        handleCountdownExpiryIfNeeded()
    }

    private func resumeCountdown() {
        beginCountdown(for: timeRemaining)
    }

    private func handleCountdownExpiryIfNeeded() {
        guard countdown.remaining(at: countdown.now) <= 0 else { return }

        // While the system or display is asleep we defer every transition until wake,
        // where `handleWake` decides what to do with the time the user spent away.
        guard isSystemAsleep == false else { return }

        switch mode {
        case .postponedWork:
            countdown.clear()
            resumeRest()
        case .resting:
            countdown.clear()

            if autoStartWorkTimer {
                // `start()` dismisses the overlays because `mode` is still `.resting`.
                start()
            } else {
                mode = .awaitingReturn
                sleepWakeObserver.stopObserving()
                // Overlay remains visible for user to click "I'm back"
            }
        case .running:
            countdown.clear()
            enterRestPhase()
        case .idle, .paused, .awaitingReturn:
            break
        }
    }

    // MARK: - Phase Transitions

    /// Resets every cycle-scoped value and returns to `.idle`. Shared by `stop()` and the
    /// wake-from-expired-rest path so both routes to idle behave identically.
    private func resetToIdle() {
        countdown.clear()
        mode = .idle
        modeBeforePause = nil
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlays.dismiss()
        sleepWakeObserver.stopObserving()
    }

    private func enterRestPhase() {
        mode = .resting
        modeBeforePause = nil
        hasPostponeBeenUsedThisCycle = false
        savedRestRemaining = nil
        overlays.show(self)
        beginCountdown(for: restDurationSecs)
    }

    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }

        mode = .resting
        modeBeforePause = nil
        savedRestRemaining = nil
        overlays.show(self)
        beginCountdown(for: saved)
    }

    // MARK: - Sleep/Wake Handling

    /// Records that the system or display went to sleep.
    ///
    /// The countdown is deliberately *not* frozen: per issue #4 the timer never stops
    /// on sleep or screen lock. We only note the moment so `handleWake` can measure
    /// how long the user was away. A duplicate notification (system *and* display
    /// sleep can both fire) keeps the original timestamp.
    private func handleSleep() {
        guard isSystemAsleep == false else { return }

        isSystemAsleep = true
        sleptAt = countdown.now
    }

    /// Reconciles the timer with the wall-clock time that elapsed while asleep.
    ///
    /// Work and postponed work follow the hybrid rule from issues #4 and #69: an
    /// absence at least as long as a full break counts as the break itself and starts
    /// a fresh work session, while a shorter absence simply continues the wall-clock
    /// countdown. A break that elapsed while away resolves on wake (auto-resuming into
    /// work when enabled). A user pause is left untouched.
    private func handleWake() {
        guard isSystemAsleep else { return }

        isSystemAsleep = false
        let awayDuration = sleptAt.map { countdown.now.timeIntervalSince($0) } ?? 0
        sleptAt = nil

        let workMode = mode == .running || mode == .postponedWork
        if workMode, awayDuration >= restDurationSecs {
            // A long absence counts as the break itself: discard the cycle and begin a
            // fresh work session. `enterRestPhase` later restores postpone availability
            // and clears any saved rest for the new cycle.
            start()
        } else if isRunning {
            // Otherwise resolve the wall-clock time that elapsed while away.
            resolveCountdownAfterWake()
        }
    }

    /// After waking, fires a transition the countdown elapsed into while away, or
    /// re-arms the expiry for the time that still remains.
    private func resolveCountdownAfterWake() {
        if timeRemaining <= 0 {
            handleCountdownExpiryIfNeeded()
        } else {
            resumeCountdown()
        }
    }

    // MARK: - Formatting

    nonisolated static func format(timeInterval interval: TimeInterval) -> String {
        let displayInterval = Int(ceil(max(0, interval)))
        let minutes = displayInterval / 60
        let seconds = displayInterval % 60
        let minutesStr = minutes.formatted(.number.precision(.integerLength(2...2)))
        let secondsStr = seconds.formatted(.number.precision(.integerLength(2...2)))
        return "\(minutesStr):\(secondsStr)"
    }
}
