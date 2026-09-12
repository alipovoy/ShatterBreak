import SwiftUI

/// An observable shell around a plan, a reducer and an effect executor.
///
/// It owns no rules: ``TimerPlan`` says what the timer is and ``TimerReducer`` what it does
/// next. This snapshots preferences, hands the reducer a moment, publishes the result and
/// asks the clock to come back.
@MainActor
@Observable
final class TimerState {
    // MARK: - Types

    /// The operational state as the UI thinks of it. Derived rather than stored: a paused
    /// work session is still a work session, so there is no "what was I doing?" to sync.
    enum Mode: Equatable {
        case idle
        case running
        case paused
        case resting
        case postponedWork
        case awaitingReturn
    }

    // MARK: - State

    /// The whole of the timer's state.
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

    /// Available only during a break, and once per cycle.
    var canPostpone: Bool {
        plan.phase == .rest && plan.pausedAt == nil && plan.postponeUsedThisCycle == false
    }

    var isRunning: Bool { plan.isCountingDown }

    var isPaused: Bool { mode == .paused }
    var isResting: Bool { mode == .resting }
    var awaitingReturn: Bool { mode == .awaitingReturn }
    var canEditDurations: Bool { mode == .idle }

    /// Settable so tests can reach a mid-cycle postpone state without driving a whole cycle.
    var hasPostponeBeenUsedThisCycle: Bool {
        get { plan.postponeUsedThisCycle }
        set { plan.postponeUsedThisCycle = newValue }
    }

    /// The break time owed back while a postpone is in flight.
    var savedRestRemaining: TimeInterval? { plan.savedRestRemaining }

    /// Identifies the interval on the clock, for views to key their refresh loop on.
    ///
    /// The phase cannot stand in: work auto-resuming after a break leaves it unchanged, so a
    /// view keyed on phase alone keeps rendering the finished interval.
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

    /// A test-supplied postpone delay taking precedence over the live preference; `nil` in
    /// the app.
    let postponeDurationOverride: Double?

    /// Tallies sessions, breaks, postpones and early returns.
    let statistics: StatisticsStore

    let defaults: any KeyValueStore
    /// Stored, not only captured, so that anything else putting a break on screen goes
    /// through the same presenter and cannot own a second window.
    let overlays: OverlayPresenter

    let clock: any TimerClock

    private let sleepWakeObserver: SleepWakeObserver
    private var executor: TimerEffectExecutor!

    private var autoStartWorkTimer: Bool {
        (defaults.string(forKey: PreferenceKeys.workStartMode)
            .flatMap { WorkStartMode(rawValue: $0) } ?? PreferenceDefaults.workStartMode) == .automatic
    }

    /// Read at the moment the reducer runs, so Preferences edits apply mid-session.
    private var preferences: TimerPreferences {
        TimerPreferences(
            workDuration: workDurationSecs,
            restDuration: restDurationSecs,
            postponeDuration: postponeDurationSecs,
            autoStartWork: autoStartWorkTimer,
            // Always the break duration for now; a parameter so making it configurable
            // stays a one-line change.
            awayResetThreshold: restDurationSecs,
            sessionLead: sessionLeadSecs
        )
    }

    /// Zero unless asked for, which is what leaves a session counting at its boundary.
    ///
    /// Gated on tracking too, and not only because the switch lives in that section: a lead
    /// running while nothing is counted would spend the credit invisibly, so turning tracking
    /// on mid-session would lose the session it used to gain.
    private var sessionLeadSecs: Double {
        guard statistics.isTrackingEnabled,
              (defaults.object(forKey: PreferenceKeys.countSessionEarly) as? Bool)
                  ?? PreferenceDefaults.countSessionEarly else { return 0 }
        return defaults.duration(forKey: PreferenceKeys.sessionLeadSecs,
                                 default: PreferenceDefaults.sessionLeadSecs)
    }

    // MARK: - Initialization

    /// - Parameters:
    ///   - isDisplayAwake: `nil` in the app, where the executor's gate instead asks
    ///     `overlays.hasAwakeScreen` — the same set of screens a break would actually be
    ///     drawn on. Tests override it directly to drive the gate without a real
    ///     ``OverlayPresenter``.
    ///   - initialPlan: the plan to open on, for previews needing a phase on screen
    ///     without driving a countdown to reach one. Set whole at construction, so
    ///     ``commit(_:)`` remains the only writer of `plan`. Nothing is scheduled for it.
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
        self.overlays = overlays
        self.postponeDurationOverride = postponeDurationSecs
        self.defaults = defaults
        self.statistics = statistics ?? StatisticsStore(defaults: defaults)
        self.sleepWakeObserver = SleepWakeObserver(notificationCenter: workspaceNotificationCenter)
        self.plan = initialPlan ?? .idle(at: clock.instant)
        self.workDurationSecs = defaults.duration(
            forKey: PreferenceKeys.workDurationSecs,
            default: PreferenceDefaults.workDurationSecs)
        self.restDurationSecs = defaults.duration(
            forKey: PreferenceKeys.restDurationSecs,
            default: PreferenceDefaults.restDurationSecs)

        let handlers = TimerEffectExecutor.Handlers(
            prepareCapture: { Task { await overlays.prepare() } },
            showOverlay: { [unowned self] in overlays.show(self, $0) },
            dismissOverlay: { overlays.dismiss() },
            record: { [unowned self] in self.statistics.record($0) },
            resetStatisticsForNewSession: { [unowned self] in self.statistics.resetForNewSessionIfEnabled() }
        )
        self.executor = TimerEffectExecutor(
            handlers: handlers,
            isDisplayAwake: isDisplayAwake ?? overlays.hasAwakeScreen
        )

        // For the object's whole life, not only while counting: subscribing per countdown is
        // how a notification comes to arrive with nobody listening.
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

    // MARK: - User Actions

    func start() { perform(.start) }
    func pause() { perform(.pause) }
    func resume() { perform(.resume) }
    func stop() { perform(.stop) }
    func postpone() { perform(.postpone) }

    /// The overlay's "I'm back" action.
    func returnToWork() { perform(.returnToWork) }

    /// Guarded to `.idle` so a second call never disrupts an active cycle. There is no
    /// session to restore: the plan is deliberately not persisted.
    func autoStartIfEnabled() {
        let enabled = defaults.object(forKey: PreferenceKeys.autoStartOnLaunch) as? Bool
        guard mode == .idle, enabled ?? PreferenceDefaults.autoStartOnLaunch else { return }
        start()
    }

    // MARK: - Reconciliation

    /// Safe to call from anywhere, as often as anything likes — that is what the reducer's
    /// idempotency buys.
    func reconcile() {
        let prefs = preferences
        commit(TimerReducer.advance(plan, to: clock.instant, prefs: prefs))
        rearm(prefs)
    }

    private func perform(_ action: TimerAction) {
        let instant = clock.instant
        let prefs = preferences
        // Act on a current plan, never a stale one.
        if TimerReducer.reconcilesInternally(action) == false {
            commit(TimerReducer.advance(plan, to: instant, prefs: prefs))
        }
        commit(TimerReducer.apply(action, to: plan, at: instant, prefs: prefs))
        rearm(prefs)
    }

    private func commit(_ result: (TimerPlan, [TimerEffect])) {
        plan = result.0
        // Called even with nothing to do: this is also where anything held back from a dark
        // screen is retried.
        executor.perform(result.1)
    }

    /// The caller's last step rather than part of ``commit(_:)``: ``perform(_:)`` commits
    /// twice, and a boundary computed from the plan in between is never reachable.
    ///
    /// Handed the `prefs` the reducer ran on rather than reading them again, so the plan and
    /// the clock armed for it come from one snapshot.
    private func rearm(_ prefs: TimerPreferences) {
        let boundary = TimerReducer.nextTransition(plan, at: clock.instant.date, prefs: prefs)
        // A break waiting for a screen has no countdown left, but still needs a retry.
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
