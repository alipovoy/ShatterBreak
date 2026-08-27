import SwiftUI

/// The remaining time, redrawn only when the text it shows would actually change.
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

/// The remaining time as of a reference date the caller supplies.
///
/// For callers already inside a ``CountdownClock``: nesting ``CountdownTextView`` in one
/// would start a second drive loop ticking the same second for the same label.
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
