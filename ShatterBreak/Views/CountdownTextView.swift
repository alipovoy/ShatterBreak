import SwiftUI

/// The remaining time, redrawn only when the text it shows would actually change.
struct CountdownTextView: View {
    let state: TimerState
    var isActive = true
    var displayStyle: CountdownDisplayStyle = .seconds

    var body: some View {
        CountdownClock(state: state, isActive: isActive, displayStyle: displayStyle) { referenceDate in
            Text(displayStyle.text(forRemaining: state.timeRemaining(at: referenceDate)))
        }
    }
}
