import Foundation

@testable import ShatterBreak

/// Drives ``TimerReducer`` over a clock the test moves by hand.
///
/// ``run(_:)``, ``drift(_:)`` and ``sleepMachine(_:)`` are the same three ways time can
/// pass that ``ManualTimerClock`` documents. No sleep notification is ever posted here,
/// deliberately: the absence must be measurable without one.
struct ReducerDriver {
    private(set) var plan: TimerPlan
    private(set) var effects: [TimerEffect] = []
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

    mutating func run(_ seconds: TimeInterval) {
        date += seconds
        uptime += seconds
        reconcile()
    }

    mutating func drift(_ seconds: TimeInterval) {
        date += seconds
        uptime += seconds
    }

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
    /// `restDuration`, as the app passes it today (#71).
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
