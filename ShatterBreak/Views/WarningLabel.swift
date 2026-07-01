import SwiftUI

/// A cautionary inline label: a warning-triangle icon beside wrapping text. Shared by the
/// Preferences warnings (``BreakTimingWarningsView`` and ``PermissionWarningView``) so
/// every inline caution reads with the same icon, tint, and font.
struct WarningLabel: View {
    let message: LocalizedStringResource

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.orange)
    }
}

#Preview {
    WarningLabel(message: .windowsOverlapWarning)
        .padding()
}
