import AppKit
import SwiftUI

/// What a break needs from the screen: ``OverlayManager`` in the app, a recorder in tests.
@MainActor
protocol BreakPresenting: AnyObject {
    /// Whether ``show(_:style:)`` would draw on anything right now.
    var hasAwakeScreen: Bool { get }
    var presentedState: TimerState? { get }
    /// Settles capture consent ahead of a break: a system dialog must not land on one.
    func prepareCapture() async
    func show(_ state: TimerState, style: OverlayPresentationStyle)
    func dismiss()
}

/// Runs ``TimerReducer`` against the real clock and performs what it asks for.
@MainActor
@Observable
final class TimerState {
    enum Mode: Equatable {
        case idle
        case running
        case paused
        case resting
        case postponedWork
        case awaitingReturn
    }

    private(set) var plan: TimerPlan

    var workDurationSecs: Double {
        didSet { defaults.set(workDurationSecs, forKey: PreferenceKeys.workDurationSecs) }
    }

    var restDurationSecs: Double {
        didSet { defaults.set(restDurationSecs, forKey: PreferenceKeys.restDurationSecs) }
    }

    let statistics: StatisticsStore
    let defaults: UserDefaults
    @ObservationIgnored let overlays: (any BreakPresenting)?
    @ObservationIgnored let now: () -> TimerInstant

    /// A parked timer shows its plan and never moves: previews and the effect sample.
    @ObservationIgnored private let isParked: Bool
    /// Every break waits here until the batch that raised it is done, then for a lit screen:
    /// macOS wakes with the display dark, and a break shown then is a break nobody sees.
    @ObservationIgnored private var pendingPresentation: OverlayPresentationStyle?
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObservers: [any NSObjectProtocol] = []

    init(
        defaults: UserDefaults = UserDefaults.standard,
        overlays: (any BreakPresenting)?,
        statistics: StatisticsStore? = nil,
        now: @escaping () -> TimerInstant = { .now },
        parkedAt parkedPlan: TimerPlan? = nil
    ) {
        self.defaults = defaults
        self.overlays = overlays
        self.statistics = statistics ?? StatisticsStore(defaults: defaults)
        self.now = now
        self.isParked = parkedPlan != nil
        self.plan = parkedPlan ?? .idle(at: now())
        self.workDurationSecs = defaults.duration(
            forKey: PreferenceKeys.workDurationSecs, default: PreferenceDefaults.workDurationSecs)
        self.restDurationSecs = defaults.duration(
            forKey: PreferenceKeys.restDurationSecs, default: PreferenceDefaults.restDurationSecs)

        guard isParked == false else { return }
        // For the object's whole life, not per countdown: a subscription made late is how a
        // notification comes to arrive with nobody listening. No queue, so delivery is
        // synchronous on the main thread NSWorkspace posts from.
        let center = NSWorkspace.shared.notificationCenter
        let sleeps = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification]
        let wakes = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]
        sleepObservers = sleeps.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemWillSleep() }
            }
        } + wakes.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemDidWake() }
            }
        }
    }

    /// A timer frozen on `plan`, touching nothing outside itself.
    static func parked(_ plan: TimerPlan, defaults: UserDefaults) -> TimerState {
        TimerState(defaults: defaults, overlays: nil, parkedAt: plan)
    }

    isolated deinit {
        boundaryTask?.cancel()
        heartbeatTask?.cancel()
        for observer in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Derived state

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

    var isRunning: Bool { plan.isCountingDown }
    var isPaused: Bool { mode == .paused }
    var isResting: Bool { mode == .resting }
    var awaitingReturn: Bool { mode == .awaitingReturn }
    var canEditDurations: Bool { mode == .idle }

    var canPostpone: Bool {
        plan.phase == .rest && plan.pausedAt == nil && plan.postponeUsedThisCycle == false
    }

    /// Changes on every phase entry, which the mode alone does not: work auto-resuming after
    /// a break leaves it `.running`.
    var countdownIntervalID: Int { plan.intervalID }

    var shouldShowTimeInMenuBar: Bool {
        switch mode {
        case .running, .paused, .postponedWork: true
        case .idle, .resting, .awaitingReturn: false
        }
    }

    func timeRemaining(at referenceDate: Date) -> TimeInterval {
        plan.remaining(at: referenceDate)
    }

    var timeRemaining: TimeInterval { timeRemaining(at: now().date) }

    nonisolated static func format(timeInterval interval: TimeInterval) -> String {
        let displayInterval = Int(ceil(max(0, interval)))
        // A closed `integerLength` range caps as well as pads, truncating minutes past 99.
        let minutes = (displayInterval / 60).formatted(.number.precision(.integerLength(2...)))
        let seconds = (displayInterval % 60).formatted(.number.precision(.integerLength(2...)))
        return "\(minutes):\(seconds)"
    }

    // MARK: - Break buttons

    /// Offered in the break's opening window only; a window longer than the break keeps it up
    /// throughout.
    func showsPostponeButton(at referenceDate: Date) -> Bool {
        guard canPostpone, flag(PreferenceKeys.allowPostpone, PreferenceDefaults.allowPostpone) else {
            return false
        }
        let elapsed = restDurationSecs - timeRemaining(at: referenceDate)
        return elapsed < duration(PreferenceKeys.postponeWindowSecs, PreferenceDefaults.postponeWindowSecs)
    }

    func showsReturnButton(at referenceDate: Date) -> Bool {
        switch mode {
        case .awaitingReturn:
            return true
        case .resting:
            return flag(PreferenceKeys.allowEarlyReturn, PreferenceDefaults.allowEarlyReturn)
                && timeRemaining(at: referenceDate)
                    <= duration(PreferenceKeys.earlyReturnLeadSecs, PreferenceDefaults.earlyReturnLeadSecs)
        default:
            return false
        }
    }

    // MARK: - Actions

    func start() { perform(.start) }
    func pause() { perform(.pause) }
    func resume() { perform(.resume) }
    func stop() { perform(.stop) }
    func postpone() { perform(.postpone) }
    func returnToWork() { perform(.returnToWork) }
    func systemWillSleep() { perform(.observedSleep) }
    func systemDidWake() { perform(.observedWake) }

    /// There is no session to restore: the plan is deliberately not persisted.
    func autoStartIfEnabled() {
        guard mode == .idle, flag(PreferenceKeys.autoStartOnLaunch, PreferenceDefaults.autoStartOnLaunch) else {
            return
        }
        start()
    }

    /// Safe to call at any moment, as often as anything likes: the reducer is idempotent.
    func reconcile() {
        guard isParked == false else { return }
        let prefs = preferences
        commit(TimerReducer.advance(plan, to: now(), prefs: prefs), prefs)
    }

    /// The reconcile and the action go to the world as one batch: performing the reconcile's
    /// effects first would show a break the action then dismisses (issue #112).
    private func perform(_ action: TimerAction) {
        guard isParked == false else { return }
        let instant = now()
        let prefs = preferences
        let (current, reconciled) = TimerReducer.reconcilesInternally(action)
            ? (plan, [])
            : TimerReducer.advance(plan, to: instant, prefs: prefs)
        let (next, applied) = TimerReducer.apply(action, to: current, at: instant, prefs: prefs)
        commit((next, reconciled + applied), prefs)
    }

    private func commit(_ result: (TimerPlan, [TimerEffect]), _ prefs: TimerPreferences) {
        plan = result.0
        execute(result.1)
        let boundary = TimerReducer.nextTransition(plan, at: now().date, prefs: prefs)
        // A break waiting for a screen has no countdown left, but still needs a retry.
        schedule(boundary: boundary, heartbeat: boundary != nil || pendingPresentation != nil)
    }

    /// Runs even for an empty batch: every reconcile is also a retry for a held break.
    private func execute(_ effects: [TimerEffect]) {
        for effect in effects {
            switch effect {
            case .prepareCapturePermissions:
                if let overlays {
                    Task { await overlays.prepareCapture() }
                }
            case .showOverlay(let style):
                pendingPresentation = style
            case .dismissOverlay:
                pendingPresentation = nil
                overlays?.dismiss()
            case .settleHeldOverlay:
                if pendingPresentation != nil {
                    pendingPresentation = .settled
                }
            case .record(let event):
                statistics.record(event)
            case .resetStatisticsForNewSession:
                statistics.resetForNewSessionIfEnabled()
            }
        }

        guard let pending = pendingPresentation, overlays?.hasAwakeScreen ?? true else { return }
        pendingPresentation = nil
        overlays?.show(self, style: pending)
    }

    /// A punctual timer for the boundary, and a coalesced heartbeat in case it goes missing.
    private func schedule(boundary: TimeInterval?, heartbeat: Bool) {
        boundaryTask?.cancel()
        boundaryTask = boundary.map { delay in
            Task(priority: .utility) { [weak self] in
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100))
                }
                guard Task.isCancelled == false else { return }
                self?.reconcile()
            }
        }

        guard heartbeat else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            return
        }
        // Left running across boundaries: its value is being the timer nothing else resets.
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task(priority: .utility) { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(10))
                guard Task.isCancelled == false else { return }
                self?.reconcile()
            }
        }
    }

    // MARK: - Preferences

    /// Read at the moment the reducer runs, so Preferences edits apply mid-session.
    private var preferences: TimerPreferences {
        TimerPreferences(
            workDuration: workDurationSecs,
            restDuration: restDurationSecs,
            postponeDuration: duration(PreferenceKeys.postponeDurationSecs, PreferenceDefaults.postponeDurationSecs),
            autoStartWork: defaults.value(
                forKey: PreferenceKeys.workStartMode, default: PreferenceDefaults.workStartMode
            ) == .automatic,
            awayResetThreshold: restDurationSecs,
            sessionLead: sessionLeadSecs
        )
    }

    /// Gated on tracking too: a lead running while nothing is counted would spend the credit
    /// unseen, and turning tracking on mid-session would lose that session.
    private var sessionLeadSecs: Double {
        guard statistics.isTrackingEnabled,
              flag(PreferenceKeys.countSessionEarly, PreferenceDefaults.countSessionEarly) else { return 0 }
        return duration(PreferenceKeys.sessionLeadSecs, PreferenceDefaults.sessionLeadSecs)
    }

    private func flag(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func duration(_ key: String, _ fallback: Double) -> Double {
        defaults.duration(forKey: key, default: fallback)
    }
}
