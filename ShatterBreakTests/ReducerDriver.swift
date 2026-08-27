import Foundation

@testable import ShatterBreak

/// Drives ``TimerReducer`` the way the app will, over a clock the test moves by hand.
///
/// The three ways time can pass are separate on purpose, because they are separate in
/// reality and the reducer must tell them apart:
///
/// - ``run(_:)`` — the machine is awake and reconciling, the ordinary case.
/// - ``drift(_:)`` — awake, but nothing reconciled: a dropped boundary timer, a throttled
///   heartbeat, App Nap. Wall time and awake time advance together, so this is *not* an
///   absence and the user is owed a full break.
/// - ``sleepMachine(_:)`` — the machine was asleep. Wall time advances and awake time does
///   not, which is what `ProcessInfo.systemUptime` does for real and is the evidence the
///   reducer measures an absence from. No notification is posted, deliberately.
struct ReducerDriver {
    private(set) var plan: TimerPlan
    /// Every effect the reducer has emitted, oldest first.
    private(set) var effects: [TimerEffect] = []
    /// The effects from the most recent call only.
    private(set) var lastEffects: [TimerEffect] = []

    var prefs: TimerPreferences
    private var date: Date
    private var uptime: TimeInterval

    init(prefs: TimerPreferences) {
        let origin = Date(timeIntervalSince1970: 0)
        self.prefs = prefs
        self.date = origin
        self.uptime = 10_000
        self.plan = .idle(at: TimerInstant(date: origin, awakeUptime: 10_000))
    }

    var instant: TimerInstant { TimerInstant(date: date, awakeUptime: uptime) }
    var now: Date { date }
    var remaining: TimeInterval { plan.remaining(at: date) }
    var phase: TimerPlan.Phase { plan.phase }

    func count(of effect: TimerEffect) -> Int {
        effects.filter { $0 == effect }.count
    }

    mutating func reconcile() {
        record(TimerReducer.advance(plan, to: instant, prefs: prefs))
    }

    mutating func act(_ action: TimerAction) {
        // The app reconciles before acting, so an action never lands on a stale plan.
        if TimerReducer.reconcilesInternally(action) == false {
            record(TimerReducer.advance(plan, to: instant, prefs: prefs))
        }
        record(TimerReducer.apply(action, to: plan, at: instant, prefs: prefs))
    }

    /// Awake and reconciling.
    mutating func run(_ seconds: TimeInterval) {
        date += seconds
        uptime += seconds
        reconcile()
    }

    /// Awake, but nothing reconciled — a lost boundary timer, not an absence.
    mutating func drift(_ seconds: TimeInterval) {
        date += seconds
        uptime += seconds
    }

    /// The machine slept: wall time moved, awake time did not.
    mutating func sleepMachine(_ seconds: TimeInterval) {
        date += seconds
    }

    private mutating func record(_ result: (TimerPlan, [TimerEffect])) {
        plan = result.0
        lastEffects = result.1
        effects += result.1
    }
}

extension TimerPreferences {
    /// Short durations so scenarios read in seconds. `awayResetThreshold` tracks
    /// `restDuration`, which is how the app always passes it today (#71).
    static func testing(
        work: TimeInterval = 10,
        rest: TimeInterval = 5,
        postpone: TimeInterval = 3,
        autoStartWork: Bool = true
    ) -> TimerPreferences {
        TimerPreferences(
            workDuration: work,
            restDuration: rest,
            postponeDuration: postpone,
            autoStartWork: autoStartWork,
            awayResetThreshold: rest
        )
    }
}
