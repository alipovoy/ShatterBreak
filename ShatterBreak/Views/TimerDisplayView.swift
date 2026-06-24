import SwiftUI

struct TimerDisplayView: View {
    let state: TimerState
    let isActive: Bool

    var body: some View {
        Group {
            if state.isRunning || state.isPaused {
                CountdownTextView(state: state, isActive: isActive)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(state.isResting ? .secondary : .primary)
            } else {
                Text(.ready)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 60)
    }
}

#Preview("Timer Display") { @MainActor in
    TimerDisplayView(state: TimerState(), isActive: true)
}
