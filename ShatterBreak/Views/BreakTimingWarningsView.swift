import SwiftUI

/// Inline cautionary labels for the break-timing contradictions reported by
/// ``BreakTimingValidator``. Renders nothing when there are no warnings, so callers can
/// place it unconditionally beneath the relevant Preferences controls.
struct BreakTimingWarningsView: View {
    let warnings: [BreakTimingWarning]

    var body: some View {
        if warnings.isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(warnings, id: \.self) { warning in
                    Label {
                        Text(message(for: warning))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func message(for warning: BreakTimingWarning) -> LocalizedStringResource {
        switch warning {
        case .postponeWindowExceedsRest: .postponeWindowExceedsRestWarning
        case .earlyReturnLeadExceedsRest: .earlyReturnLeadExceedsRestWarning
        case .windowsOverlap: .windowsOverlapWarning
        }
    }
}

#Preview {
    BreakTimingWarningsView(warnings: [.postponeWindowExceedsRest, .windowsOverlap])
        .padding()
}
