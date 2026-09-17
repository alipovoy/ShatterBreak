import AppKit
import Testing

@testable import ShatterBreak

/// The status item reacts to a preference written elsewhere, to the phase on the clock and
/// to being released — none of which reaches it through SwiftUI any more.
@Suite("Menu bar controller", .tags(.timerState), .timeLimit(.minutes(1)))
struct MenuBarControllerTests {
    @Test("A style written to the store reaches the item")
    @MainActor
    func styleChangeReachesTheItem() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 1500
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.settle()
        #expect(
            controller.countdownText.isEmpty,
            "The default style shows no countdown, so the item draws the icon alone."
        )

        environment.setMenuBarTimerStyle(.seconds)
        await environment.waitUntil { controller.countdownText.isEmpty == false }
        #expect(
            controller.countdownText == "25:00",
            "A style change should put the countdown beside the icon."
        )
    }

    @Test("A postponed session counts its own delay down, not the work duration")
    @MainActor
    func postponedWorkCountsTheDelay() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState(postponeDurationSecs: 300)
        state.workDurationSecs = 6000
        state.restDurationSecs = 60
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.waitUntil { controller.countdownText == "100:00" }

        await environment.advanceUntil(by: 6000, maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should reach a break before postponing.")

        state.postpone()
        #expect(state.mode == .postponedWork, "The test setup should reach postponed work.")
        await environment.waitUntil { controller.countdownText == "05:00" }
        #expect(
            controller.countdownText == "05:00",
            "A postpone puts its own delay on the clock, which is what the item must draw."
        )
    }

    /// A minute already spent: a countdown that never renders keeps the starting minute.
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

        await environment.waitUntil { controller.countdownText == "24:00" }
        #expect(
            controller.countdownText == "24:00",
            "A wall-clock reference date reads 00:00; a countdown that never renders reads 25:00."
        )
    }

    @Test("A break leaves the icon alone in the menu bar")
    @MainActor
    func aBreakDrawsNoCountdown() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState()
        state.workDurationSecs = 60
        state.restDurationSecs = 60
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.waitUntil { controller.countdownText == "01:00" }

        await environment.advanceUntil(by: 60, maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should reach a break.")
        await environment.waitUntil { controller.countdownText.isEmpty }
        #expect(
            controller.countdownText.isEmpty,
            "The overlay carries the break's countdown; the menu bar goes back to the icon."
        )
    }

    @Test("The popover's anchor stays where it was parked when the item resizes")
    @MainActor
    func theAnchorDoesNotFollowTheItem() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState()
        state.workDurationSecs = 1500
        let controller = environment.makeMenuBarController(state: state)

        let anchor = controller.stageAnchor()
        let parked = controller.anchorOrigin
        #expect(anchor != nil && parked != nil, "Opening the menu should park an anchor over the item.")

        state.start()
        await environment.waitUntil { controller.countdownText.isEmpty == false }
        #expect(
            controller.anchorOrigin == parked,
            "A countdown appearing widens the item; the anchor — and so the open menu — must not move with it."
        )
    }

    @Test(
        "A click opens the menu unless one is genuinely up",
        arguments: [
            MenuBarClickCase(intendedOpen: false, popoverIsShown: false, opens: true, note: "Nothing up."),
            MenuBarClickCase(intendedOpen: true, popoverIsShown: true, opens: false, note: "A menu is up."),
            MenuBarClickCase(
                intendedOpen: false,
                popoverIsShown: true,
                opens: true,
                note: "The second of two quick clicks: the first one's menu is still animating out."
            ),
            MenuBarClickCase(
                intendedOpen: true,
                popoverIsShown: false,
                opens: true,
                note: "The menu was dismissed by a click elsewhere, so the intent is stale."
            )
        ]
    )
    @MainActor
    func aClickOpensUnlessAMenuIsUp(_ testCase: MenuBarClickCase) {
        #expect(
            MenuBarController.clickOpensMenu(
                intendedOpen: testCase.intendedOpen,
                popoverIsShown: testCase.popoverIsShown
            ) == testCase.opens,
            "\(testCase.note)"
        )
    }

    @Test("A released controller gives its status item back")
    @MainActor
    func releasingTheControllerReleasesTheStatusItem() async {
        let environment = TestEnvironment()
        environment.setMenuBarTimerStyle(.seconds)
        let state = environment.makeTimerState()
        weak var released: MenuBarController?

        do {
            let controller = environment.makeMenuBarController(state: state)
            released = controller
            state.start()
            await environment.waitUntil { controller.countdownText.isEmpty == false }
        }

        await environment.settle()
        #expect(
            released == nil,
            "A refresh loop holding its controller would outlive the test and keep the item in the status bar."
        )
    }
}

struct MenuBarClickCase: Sendable {
    let intendedOpen: Bool
    let popoverIsShown: Bool
    let opens: Bool
    let note: String
}
