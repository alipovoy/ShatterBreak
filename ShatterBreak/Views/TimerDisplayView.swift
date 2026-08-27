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

private extension TimerState {
    /// A timer parked in a phase, reading and writing nothing outside the preview.
    static func preview(_ plan: TimerPlan) -> TimerState {
        TimerState(overlays: .disabled, defaults: InMemoryKeyValueStore(), showing: plan)
    }
}

#Preview("Working") { @MainActor in
    TimerDisplayView(state: .preview(.starting(.work, duration: 1_500)), isActive: true)
        .padding()
}

#Preview("Resting") { @MainActor in
    TimerDisplayView(state: .preview(.starting(.rest, duration: 300)), isActive: true)
        .padding()
}

#Preview("Paused") { @MainActor in
    // Pausing is not a phase, so it is the one state `starting` cannot express alone.
    var plan = TimerPlan.starting(.work, duration: 1_500)
    plan.pausedAt = plan.startedAt.addingTimeInterval(320)

    return TimerDisplayView(state: .preview(plan), isActive: true)
        .padding()
}

#Preview("Idle") { @MainActor in
    TimerDisplayView(state: .preview(.idle(at: .now)), isActive: true)
        .padding()
}
