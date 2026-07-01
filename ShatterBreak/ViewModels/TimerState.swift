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

    /// The saved break remainder while a postpone is in flight. Internal (not `private`)
    /// so the sleep/wake extension in `TimerState+SleepWake.swift` can reconcile it.
    var savedRestRemaining: TimeInterval?

    /// A test-supplied postpone delay that takes precedence over the live preference;
    /// `nil` in the app so the value is read from preferences. Read by the break-button
    /// extension in `TimerState+BreakButtons.swift`.
    let postponeDurationOverride: Double?

    /// The mode to restore when a user pause resumes; `nil` when not paused.
    private var modeBeforePause: Mode?

    /// The moment sleep/display-off began. Doubles as the "asleep" flag — non-`nil` while
    /// asleep — and measures how long the user was away on wake. Internal for the
    /// sleep/wake extension.
    var sleptAt: Date?

    /// Internal (not `private`) so the break-button extension can read the clock.
    let countdown: Countdown
    private let sleepWakeObserver: SleepWakeObserver
    private let overlays: OverlayPresenter
    /// Internal (not `private`) so the break-button extension can read live preferences.
    let defaults: any KeyValueStore

    /// Whether work auto-starts after a break. Internal for the sleep/wake extension.
    var autoStartWorkTimer: Bool {
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

    /// Internal so the sleep/wake extension can re-arm the countdown after waking.
    func resumeCountdown() {
        beginCountdown(for: timeRemaining)
    }

    /// Internal so the sleep/wake extension can fire a transition the countdown elapsed
    /// into while the machine was asleep.
    func handleCountdownExpiryIfNeeded() {
        guard countdown.remaining(at: countdown.now) <= 0 else { return }

        // While the system or display is asleep we defer every transition until wake,
        // where `handleWake` decides what to do with the time the user spent away.
        guard sleptAt == nil else { return }

        switch mode {
        case .postponedWork:
            countdown.clear()
            resumeRest()
        case .resting:
            // The break overlay is already on screen, so keep it up rather than re-present.
            finishBreak(presentingOverlay: false)
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
        beginRest(for: restDurationSecs, refreshingPostpone: true)
    }

    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }

        beginRest(for: saved, refreshingPostpone: false)
    }

    /// Enters the rest phase with `duration` on the clock and shows the break overlay.
    ///
    /// `refreshingPostpone` restores postpone availability for a brand-new cycle's break
    /// (entered from work); a resumed postpone remainder keeps its already-spent state.
    /// Internal so the sleep/wake extension can resume a prorated break on wake.
    func beginRest(for duration: TimeInterval, refreshingPostpone: Bool) {
        mode = .resting
        modeBeforePause = nil
        if refreshingPostpone {
            hasPostponeBeenUsedThisCycle = false
        }
        savedRestRemaining = nil
        overlays.show(self)
        beginCountdown(for: duration)
    }

    /// Completes a break: auto-starts the next work session when enabled, otherwise parks
    /// in the break-end window and waits for the user.
    ///
    /// `presentingOverlay` shows the window for the wake path where an absence served as
    /// the break and no overlay is on screen yet (the user was working); the rest-expiry
    /// path already has one up. Internal so the sleep/wake extension can drive it after an
    /// absence that replaced the break.
    func finishBreak(presentingOverlay: Bool) {
        if autoStartWorkTimer {
            // `start()` dismisses any break overlay because `mode` is still `.resting`.
            start()
        } else {
            awaitReturn(presentingOverlay: presentingOverlay)
        }
    }

    /// Parks in `.awaitingReturn`, discarding any in-flight saved break, and optionally
    /// presents the break-end window.
    private func awaitReturn(presentingOverlay: Bool) {
        countdown.clear()
        mode = .awaitingReturn
        savedRestRemaining = nil
        if presentingOverlay {
            overlays.show(self)
        }
        sleepWakeObserver.stopObserving()
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
