import Foundation
import Testing

@testable import ShatterBreak

/// The properties the whole design rests on.
///
/// Everything above the reducer — a boundary timer, a coalesced heartbeat, wake
/// notifications, the menu opening — is allowed to call `advance` at any moment, as often
/// as it likes, and none of them is trusted. That is only safe if reconciling is
/// idempotent and never crosses more than one boundary at a time. If these fail, the
/// design is broken, not the test.
@Suite("Timer reducer laws", .tags(.timerState))
struct TimerReducerLawTests {
    /// A plan/instant pair generator wide enough to reach every phase, both sides of every
    /// boundary, paused and running, with and without an absence in flight.
    private struct Scenario {
        var plan: TimerPlan
        var instant: TimerInstant
        var prefs: TimerPreferences
        var description: String
    }

    private func scenarios(seed: UInt64, count: Int) -> [Scenario] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return (0..<count).map { makeScenario(index: $0, seed: seed, rng: &rng) }
    }

    private func makeScenario(index: Int, seed: UInt64, rng: inout SeededRandomNumberGenerator) -> Scenario {
        let phases: [TimerPlan.Phase] = [.idle, .work, .rest, .postponedWork, .awaitingReturn]
        let origin = Date(timeIntervalSince1970: 1_000_000)

        let phase = phases[Int.random(in: 0..<phases.count, using: &rng)]
        let rest = Double.random(in: 30...600, using: &rng)
        let duration = Double.random(in: 1...1_800, using: &rng)
        // Elapsed straddles the boundary in both directions, so roughly half of these land
        // on a transition and half do not.
        let elapsed = Double.random(in: 0...(duration * 2), using: &rng)
        let awakeGap = Double.random(in: 0...120, using: &rng)
        // Wall time never runs slower than awake time; the excess is machine sleep.
        let sleptGap = Bool.random(using: &rng) ? Double.random(in: 0...7_200, using: &rng) : 0
        let lastSeen = TimerInstant(date: origin, awakeUptime: 50_000)

        let plan = TimerPlan(
            phase: phase,
            startedAt: origin.addingTimeInterval(-elapsed),
            duration: phase == .idle || phase == .awaitingReturn ? 0 : duration,
            pausedAt: Bool.random(using: &rng)
                ? origin.addingTimeInterval(-Double.random(in: 0...elapsed, using: &rng))
                : nil,
            intervalID: index,
            savedRestRemaining: Bool.random(using: &rng) ? Double.random(in: 0...rest, using: &rng) : nil,
            postponeUsedThisCycle: Bool.random(using: &rng),
            unattendedSince: Bool.random(using: &rng)
                ? origin.addingTimeInterval(-Double.random(in: 0...3_600, using: &rng))
                : nil,
            absenceCreditedAt: Bool.random(using: &rng)
                ? origin.addingTimeInterval(-Double.random(in: 0...600, using: &rng))
                : nil,
            lastSeen: lastSeen
        )
        let prefs = TimerPreferences(
            workDuration: Double.random(in: 60...1_800, using: &rng),
            restDuration: rest,
            postponeDuration: Double.random(in: 60...600, using: &rng),
            autoStartWork: Bool.random(using: &rng),
            awayResetThreshold: rest
        )
        return Scenario(
            plan: plan,
            instant: TimerInstant(
                date: origin.addingTimeInterval(awakeGap + sleptGap),
                awakeUptime: lastSeen.awakeUptime + awakeGap
            ),
            prefs: prefs,
            description: """
            seed \(seed) case \(index): phase \(phase), duration \(duration), elapsed \(elapsed), \
            awakeGap \(awakeGap), sleptGap \(sleptGap), paused \(plan.pausedAt != nil), \
            unattended \(plan.unattendedSince != nil)
            """
        )
    }

    @Test("reconciling twice for the same moment changes nothing the second time")
    func advanceIsIdempotent() {
        // Fixed seeds so a failure reproduces exactly; the description carries the case.
        for seed in [0x5EED_0001, 0x5EED_0002, 0x5EED_0003] as [UInt64] {
            for scenario in scenarios(seed: seed, count: 400) {
                let (once, _) = TimerReducer.advance(scenario.plan, to: scenario.instant, prefs: scenario.prefs)
                let (twice, replayed) = TimerReducer.advance(once, to: scenario.instant, prefs: scenario.prefs)

                #expect(twice == once, "A replayed reconcile must not move the plan — \(scenario.description)")
                #expect(
                    replayed.isEmpty,
                    "A replayed reconcile must owe the world nothing — \(scenario.description)"
                )
            }
        }
    }

    @Test("one reconcile crosses at most one boundary")
    func advanceCrossesAtMostOneBoundary() {
        for scenario in scenarios(seed: 0x5EED_0004, count: 800) {
            let (_, effects) = TimerReducer.advance(scenario.plan, to: scenario.instant, prefs: scenario.prefs)
            let completions = effects.filter { $0 == .record(.workSessionCompleted) || $0 == .record(.breakCompleted) }

            // The trap this rules out: a `while remaining <= 0 { cross() }` loop replaying a
            // three-hour sleep as four cycles, four completed sessions and four overlays.
            #expect(
                completions.count <= 1,
                "A single reconcile must never bank more than one completion — \(scenario.description)"
            )
            #expect(
                effects.filter { $0 == .showOverlay(.animated) || $0 == .showOverlay(.settled) }.count <= 1,
                "A single reconcile must never queue more than one overlay — \(scenario.description)"
            )
        }
    }

    @Test("reconciling never resurrects a stopped timer or moves a paused one")
    func inertStatesStayInert() {
        for scenario in scenarios(seed: 0x5EED_0005, count: 800) {
            let (next, effects) = TimerReducer.advance(scenario.plan, to: scenario.instant, prefs: scenario.prefs)

            if scenario.plan.phase == .idle {
                #expect(next.phase == .idle, "An idle timer must stay idle — \(scenario.description)")
                #expect(effects.isEmpty, "An idle timer owes nothing — \(scenario.description)")
            }
            if scenario.plan.pausedAt != nil {
                #expect(next.pausedAt == scenario.plan.pausedAt, "A pause must survive — \(scenario.description)")
                #expect(
                    next.remaining(at: scenario.instant.date) == scenario.plan.remaining(at: scenario.instant.date),
                    "A paused countdown must not move — \(scenario.description)"
                )
                #expect(effects.isEmpty, "A paused timer owes nothing — \(scenario.description)")
            }
        }
    }

    @Test("a live phase always leaves a countdown someone can reach zero on")
    func liveStatesNeverStrandAtZero() {
        for scenario in scenarios(seed: 0x5EED_0006, count: 800) {
            let (next, _) = TimerReducer.advance(scenario.plan, to: scenario.instant, prefs: scenario.prefs)
            guard next.isCountingDown else { continue }

            // The 00:00 stall in one line: a counting phase whose deadline is already behind
            // it, with nothing left to fire. Reconciling can only ever produce a phase that
            // still has time on it, so the symptom has nowhere to come from.
            #expect(
                next.rawRemaining(at: scenario.instant.date) > 0,
                "A reconcile must not leave a live phase already expired — \(scenario.description)"
            )
        }
    }
}
