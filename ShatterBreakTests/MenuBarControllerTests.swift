import AppKit
import Testing

@testable import ShatterBreak

/// Covers what the status item now does for itself — react to a preference written
/// elsewhere, follow the phase on the clock, draw against that clock, and give the item
/// back — because none of it reaches the status item through SwiftUI any more.
@Suite("Menu bar controller", .tags(.timerState), .timeLimit(.minutes(1)))
struct MenuBarControllerTests {
    @Test("A style written to the store re-pins the item")
    @MainActor
    func styleChangeRepinsTheItem() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 1500
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.settle()
        #expect(
            controller.pinnedLength == NSStatusItem.variableLength,
            "The default style shows no countdown, so the item stays free to size itself."
        )

        environment.setMenuBarTimerStyle(.seconds)
        await environment.waitUntil { controller.pinnedLength > 0 }
        #expect(
            controller.pinnedLength > 0,
            "A style change should pin the item to the countdown's widest string."
        )
    }

    @Test("A postponed session is measured against the postpone delay, not the work duration")
    @MainActor
    func postponedWorkPinsToItsOwnDuration() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState(postponeDurationSecs: 300)
        // Six digits against the postpone delay's five, so the two widths cannot coincide.
        state.workDurationSecs = 6000
        state.restDurationSecs = 60
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.waitUntil { controller.pinnedLength > 0 }
        let workLength = controller.pinnedLength
        #expect(workLength > 0, "A running session should pin the item.")

        await environment.advanceUntil(by: 6000, maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should reach a break before postponing.")

        state.postpone()
        #expect(state.mode == .postponedWork, "The test setup should reach postponed work.")
        await environment.waitUntil { controller.pinnedLength > 0 && controller.pinnedLength != workLength }
        #expect(
            controller.pinnedLength < workLength,
            "A postpone counts down 05:00, which is narrower than the work session's 100:00."
        )
    }

    /// Asserts on a minute the countdown has already spent, not on the one it starts at:
    /// measuring the width leaves the widest candidate — "25:00" here — sitting in the
    /// button, so a fixture asserting the starting minute cannot tell a render from residue.
    @Test("The countdown is drawn against the timer's clock")
    @MainActor
    func countdownRendersAgainstTheTimersClock() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState()
        state.workDurationSecs = 1500
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.advanceTime(by: 60)

        await environment.waitUntil(attempts: 600) { controller.countdownText == "24:00" }
        #expect(
            controller.countdownText == "24:00",
            """
            A wall-clock reference date measures a plan the test clock started in 1970 as long \
            expired; a countdown that never renders leaves the measured "25:00" behind.
            """
        )
    }

    @Test("A released controller gives its status item back")
    @MainActor
    func releasingTheControllerReleasesTheStatusItem() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState()
        state.workDurationSecs = 1500
        weak var released: MenuBarController?

        do {
            let controller = environment.makeMenuBarController(state: state)
            released = controller
            state.start()
            await environment.waitUntil { controller.pinnedLength > 0 }
        }

        await environment.settle()
        #expect(
            released == nil,
            "A refresh loop holding its controller would outlive the test and keep the item in the status bar."
        )
    }
}
