import SwiftUI

struct CountdownTextView: View {
    let state: TimerState
    var isActive = true
    var displayStyle: CountdownDisplayStyle = .seconds

    var body: some View {
        CountdownClock(state: state, isActive: isActive, displayStyle: displayStyle) { referenceDate in
            CountdownLabel(state: state, at: referenceDate, displayStyle: displayStyle)
        }
    }
}

/// For callers already inside a ``CountdownClock``, which would otherwise run a second loop.
struct CountdownLabel: View {
    let state: TimerState
    let referenceDate: Date
    var displayStyle: CountdownDisplayStyle = .seconds

    init(state: TimerState, at referenceDate: Date, displayStyle: CountdownDisplayStyle = .seconds) {
        self.state = state
        self.referenceDate = referenceDate
        self.displayStyle = displayStyle
    }

    var body: some View {
        Text(displayStyle.text(forRemaining: state.timeRemaining(at: referenceDate)))
    }
}
