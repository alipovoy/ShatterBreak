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

    /// Why the timer is paused, carrying the mode to restore on resume.
    ///
    /// Only a `.system` pause auto-resumes on wake; a `.user` pause stays paused
    /// until the user resumes. Keeping provenance in one value makes that rule a
    /// single, hard-to-misread switch.
    private enum PauseReason {
        case user(previous: Mode)
        case system(previous: Mode)

        /// The mode that was active before pausing.
        var previousMode: Mode {
            switch self {
            case .user(let previous), .system(let previous): previous
            }
        }
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

    var postponeDurationSecs: Double = 60

    /// Whether postpone is available: only when resting and not yet used this cycle.
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
    private var pauseReason: PauseReason?

    private let countdown: Countdown
    private let sleepWakeObserver: SleepWakeObserver
    private let overlays: OverlayPresenter
    private let defaults: any KeyValueStore

    private var autoStartWorkTimer: Bool {
        (defaults.string(forKey: PreferenceKeys.workStartMode)
            .flatMap { WorkStartMode(rawValue: $0) } ?? PreferenceDefaults.workStartMode) == .automatic
    }

    // MARK: - Initialization

    init(
        overlays: OverlayPresenter,
        postponeDurationSecs: Double = 60,
        defaults: any KeyValueStore = UserDefaults.standard,
        scheduler: (any CountdownScheduler)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.overlays = overlays
        self.postponeDurationSecs = postponeDurationSecs
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
        postponeDurationSecs: Double = 60,
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
        pauseReason = nil
        beginCountdown(for: workDurationSecs)
    }

    func pause() {
        switch mode {
        case .running, .postponedWork:
            let previousMode = mode
            countdown.freeze()
            pauseReason = .user(previous: previousMode)
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

        let resumedMode = pauseReason?.previousMode ?? .running
        pauseReason = nil
        mode = resumedMode
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

        switch mode {
        case .postponedWork:
            countdown.clear()
            resumeRest()
        case .resting:
            guard isSystemAsleep == false else { return }

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
        pauseReason = nil
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlays.dismiss()
        sleepWakeObserver.stopObserving()
    }

    private func enterRestPhase() {
        mode = .resting
        pauseReason = nil
        hasPostponeBeenUsedThisCycle = false
        savedRestRemaining = nil
        overlays.show(self)
        beginCountdown(for: restDurationSecs)
    }

    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }

        mode = .resting
        pauseReason = nil
        savedRestRemaining = nil
        overlays.show(self)
        beginCountdown(for: saved)
    }

    // MARK: - Sleep/Wake Handling

    private func handleSleep() {
        isSystemAsleep = true

        guard mode == .running || mode == .postponedWork else { return }

        let previousMode = mode
        countdown.freeze()
        pauseReason = .system(previous: previousMode)
        mode = .paused
    }

    private func handleWake() {
        isSystemAsleep = false

        if mode == .resting {
            if countdown.remaining(at: countdown.now) <= 0 {
                resetToIdle()
            }

            return
        }

        // Only a system auto-pause resumes on wake; a user pause stays paused.
        guard case .system(let previousMode) = pauseReason else { return }

        pauseReason = nil
        mode = previousMode
        resumeCountdown()
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
