import SwiftUI

/// The app's view of the timer: an observable shell around a plan, a reducer and an
/// effect executor.
///
/// It owns no rules. Every question about what the timer *is* is answered by
/// ``TimerPlan`` and every question about what it *does next* by ``TimerReducer``; this
/// type snapshots preferences, hands the reducer a moment, publishes the result, and asks
/// the clock to come back. That leaves one place where state changes, and it is a pure
/// function — which is the point of the exercise (#89).
@MainActor
@Observable
final class TimerState {
    // MARK: - Types

    /// The current operational state, as the UI thinks of it.
    ///
    /// Derived from the plan rather than stored: a paused work session is still a work
    /// session with a pause on it, so there is no "what was I doing before?" to keep in
    /// sync with anything.
    enum Mode: Equatable {
        case idle
        case running
        case paused
        case resting
        case postponedWork
        case awaitingReturn
    }

    // MARK: - State

    /// The whole of the timer's state. Observable, so a view that reads any derived value
    /// registers a dependency on the one thing that changes.
    private(set) var plan: TimerPlan

    var mode: Mode {
        guard plan.pausedAt == nil else { return .paused }
        switch plan.phase {
        case .idle: return .idle
        case .work: return .running
        case .rest: return .resting
        case .postponedWork: return .postponedWork
        case .awaitingReturn: return .awaitingReturn
        }
    }

    var workDurationSecs: Double {
        didSet {
            defaults.set(workDurationSecs, forKey: PreferenceKeys.workDurationSecs)
        }
    }

    var restDurationSecs: Double {
        didSet {
            defaults.set(restDurationSecs, forKey: PreferenceKeys.restDurationSecs)
        }
    }

    /// Whether postpone is available this cycle: only during a break, not yet used.
    var canPostpone: Bool {
        plan.phase == .rest && plan.pausedAt == nil && plan.postponeUsedThisCycle == false
    }

    /// Whether the timer is actively counting down (work, rest, or postponed work).
    var isRunning: Bool { plan.isCountingDown }

    var isPaused: Bool { mode == .paused }
    var isResting: Bool { mode == .resting }
    var awaitingReturn: Bool { mode == .awaitingReturn }
    var canEditDurations: Bool { mode == .idle }

    /// Internal (not `private`) so tests can put the timer into a mid-cycle postpone state
    /// without driving a whole cycle to reach it.
    var hasPostponeBeenUsedThisCycle: Bool {
        get { plan.postponeUsedThisCycle }
        set { plan.postponeUsedThisCycle = newValue }
    }

    /// The break time owed back while a postpone is in flight.
    var savedRestRemaining: TimeInterval? { plan.savedRestRemaining }

    /// Identifies the interval currently on the clock, changing on every phase entry.
    ///
    /// What a view keys its refresh loop on. The phase cannot stand in for it: work
    /// auto-resuming after a break leaves the phase exactly where it was, so a view keyed
    /// on the phase alone never notices the new interval and keeps rendering the finished
    /// one (issue #108).
    var countdownIntervalID: Int { plan.intervalID }

    /// The remaining time at the clock's current moment.
    var timeRemaining: TimeInterval { plan.remaining(at: clock.instant.date) }

    var shouldShowTimeInMenuBar: Bool {
        switch mode {
        case .running, .paused, .postponedWork:
            return true
        case .idle, .resting, .awaitingReturn:
            return false
        }
    }

    var formattedTimeRemaining: String {
        formattedTimeRemaining(at: clock.instant.date)
    }

    // MARK: - Collaborators

    /// A test-supplied postpone delay that takes precedence over the live preference;
    /// `nil` in the app so the value is read from preferences. Read by the break-button
    /// extension in `TimerState+BreakButtons.swift`.
    let postponeDurationOverride: Double?

    /// Tallies completed sessions, breaks, postpones, and early returns (issue #10).
    let statistics: StatisticsStore

    /// Internal (not `private`) so the break-button extension can read live preferences.
    let defaults: any KeyValueStore

    /// Internal so the break-button extension can read the clock.
    let clock: any TimerClock

    private let sleepWakeObserver: SleepWakeObserver
    private var executor: TimerEffectExecutor!

    /// Whether work auto-starts after a break.
    private var autoStartWorkTimer: Bool {
        (defaults.string(forKey: PreferenceKeys.workStartMode)
            .flatMap { WorkStartMode(rawValue: $0) } ?? PreferenceDefaults.workStartMode) == .automatic
    }

    /// The preference values the reducer needs, read at the moment it runs so edits in
    /// Preferences apply mid-session.
    private var preferences: TimerPreferences {
        TimerPreferences(
            workDuration: workDurationSecs,
            restDuration: restDurationSecs,
            postponeDuration: postponeDurationSecs,
            autoStartWork: autoStartWorkTimer,
            // Always the break duration for now. Making it configurable is #71, and this
            // being a parameter from the start is what keeps that a one-line change.
            awayResetThreshold: restDurationSecs
        )
    }

    // MARK: - Initialization

    /// - Parameter initialPlan: the plan to open on, for previews and design work that
    ///   need a phase on screen without driving a countdown to reach one. Passed as a
    ///   whole value at construction rather than poked into a live timer, so `plan` still
    ///   has exactly one writer afterwards: ``commit(_:)``, with whatever the reducer
    ///   returned. Nothing is scheduled for it — a preview renders a plan, it does not run
    ///   one.
    init(
        overlays: OverlayPresenter,
        postponeDurationSecs: Double? = nil,
        defaults: any KeyValueStore = UserDefaults.standard,
        clock: (any TimerClock)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        statistics: StatisticsStore? = nil,
        isDisplayAwake: (@MainActor () -> Bool)? = nil,
        showing initialPlan: TimerPlan? = nil
    ) {
        let clock = clock ?? SystemTimerClock()
        self.clock = clock
        self.postponeDurationOverride = postponeDurationSecs
        self.defaults = defaults
        self.statistics = statistics ?? StatisticsStore(defaults: defaults)
        self.sleepWakeObserver = SleepWakeObserver(notificationCenter: workspaceNotificationCenter)
        self.plan = initialPlan ?? .idle(at: clock.instant)
        self.workDurationSecs = Self.loadDuration(
            forKey: PreferenceKeys.workDurationSecs,
            defaultValue: PreferenceDefaults.workDurationSecs,
            defaults: defaults)
        self.restDurationSecs = Self.loadDuration(
            forKey: PreferenceKeys.restDurationSecs,
            defaultValue: PreferenceDefaults.restDurationSecs,
            defaults: defaults)

        let handlers = TimerEffectExecutor.Handlers(
            prepareCapture: { overlays.prepare() },
            showOverlay: { [unowned self] in overlays.show(self, $0) },
            dismissOverlay: { overlays.dismiss() },
            record: { [unowned self] in self.statistics.record($0) },
            resetStatisticsForNewSession: { [unowned self] in self.statistics.resetForNewSessionIfEnabled() }
        )
        self.executor = isDisplayAwake.map { TimerEffectExecutor(handlers: handlers, isDisplayAwake: $0) }
            ?? TimerEffectExecutor(handlers: handlers)

        // Observed for the object's whole life rather than only while counting. There is no
        // state to strand that way, and the alternative — subscribing per countdown — is
        // how a notification came to arrive with nobody listening (#87).
        sleepWakeObserver.startObserving(
            onSleep: { [weak self] in self?.perform(.observedSleep) },
            onWake: { [weak self] in self?.perform(.observedWake) }
        )
    }

    convenience init(
        postponeDurationSecs: Double? = nil,
        defaults: any KeyValueStore = UserDefaults.standard,
        clock: (any TimerClock)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.init(
            overlays: .live(defaults: defaults),
            postponeDurationSecs: postponeDurationSecs,
            defaults: defaults,
            clock: clock,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    isolated deinit {
        clock.stop()
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

    func start() { perform(.start) }
    func pause() { perform(.pause) }
    func resume() { perform(.resume) }
    func stop() { perform(.stop) }
    func postpone() { perform(.postpone) }

    /// The overlay's "I'm back" action.
    func returnToWork() { perform(.returnToWork) }

    /// Starts a work session at launch when the user has opted in.
    ///
    /// Guarded to `.idle` so it only fires for a fresh launch and never disrupts an
    /// already-active cycle if invoked more than once. There is no session to restore: the
    /// plan is deliberately not persisted, so a relaunch or a crash starts clean.
    func autoStartIfEnabled() {
        let enabled = defaults.object(forKey: PreferenceKeys.autoStartOnLaunch) as? Bool
        guard mode == .idle, enabled ?? PreferenceDefaults.autoStartOnLaunch else { return }
        start()
    }

    // MARK: - Reconciliation

    /// Brings the published state up to date with the current moment.
    ///
    /// Safe to call from anywhere, at any time, as often as anything likes — that is the
    /// contract the reducer's idempotency buys, and the reason a lost callback here costs a
    /// tick rather than a session.
    func reconcile() {
        commit(TimerReducer.advance(plan, to: clock.instant, prefs: preferences))
    }

    private func perform(_ action: TimerAction) {
        let instant = clock.instant
        let prefs = preferences
        // Act on a current plan, never a stale one. `observedWake` reconciles internally,
        // because the absence it resolves is measured from state it then retires.
        if action != .observedWake {
            commit(TimerReducer.advance(plan, to: instant, prefs: prefs))
        }
        commit(TimerReducer.apply(action, to: plan, at: instant, prefs: prefs))
    }

    private func commit(_ result: (TimerPlan, [TimerEffect])) {
        plan = result.0
        // Always called, even with nothing to do: performing effects is also when anything
        // held back from a dark screen gets retried, so every reconcile is a retry.
        executor.perform(result.1)
        rearm()
    }

    private func rearm() {
        let boundary = plan.isCountingDown
            ? max(0, plan.rawRemaining(at: clock.instant.date))
            : nil
        // A break waiting for a screen has no countdown left but still needs someone to
        // come back and try again.
        let pending = boundary != nil || executor.deferredPresentation != nil
        clock.schedule(nextBoundary: boundary, heartbeat: pending) { [weak self] in
            self?.reconcile()
        }
    }

    // MARK: - Display

    func timeRemaining(at referenceDate: Date) -> TimeInterval {
        plan.remaining(at: referenceDate)
    }

    func formattedTimeRemaining(at referenceDate: Date) -> String {
        Self.format(timeInterval: timeRemaining(at: referenceDate))
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
