import AppKit
import Testing

@testable import ShatterBreak

/// Covers the two signals the status item reacts to on its own — a preference written
/// elsewhere and the phase now on the clock — because neither reaches it through SwiftUI
/// any more.
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
            controller.statusItem.length == NSStatusItem.variableLength,
            "The default style shows no countdown, so the item stays free to size itself."
        )

        environment.setMenuBarTimerStyle(.seconds)
        await environment.waitUntil { controller.statusItem.length > 0 }
        #expect(
            controller.statusItem.length > 0,
            "A style change should pin the item to the countdown's widest string."
        )
    }

    @Test("A postponed session is measured against the postpone delay, not the work duration")
    @MainActor
    func postponedWorkPinsToItsOwnDuration() async {
        let environment = TestEnvironment()
        environment.defaults.set(MenuBarTimerStyle.seconds.rawValue, forKey: PreferenceKeys.menuBarTimerStyle)
        let state = environment.makeTimerState(postponeDurationSecs: 300)
        // Six digits against the postpone delay's five, so the two widths cannot coincide.
        state.workDurationSecs = 6000
        state.restDurationSecs = 60
        let controller = environment.makeMenuBarController(state: state)

        state.start()
        await environment.waitUntil { controller.statusItem.length > 0 }
        let workLength = controller.statusItem.length
        #expect(workLength > 0, "A running session should pin the item.")

        await environment.advanceUntil(by: 6000, maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should reach a break before postponing.")

        state.postpone()
        #expect(state.mode == .postponedWork, "The test setup should reach postponed work.")
        await environment.waitUntil { controller.statusItem.length > 0 && controller.statusItem.length != workLength }
        #expect(
            controller.statusItem.length < workLength,
            "A postpone counts down 05:00, which is narrower than the work session's 100:00."
        )
    }
}
