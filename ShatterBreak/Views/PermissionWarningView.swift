import SwiftUI

/// An inline caution about a missing screen-capture consent, above the one action that
/// grants it. Shared by both consents the Shatter effect depends on, so they read
/// identically and differ only in wording and destination.
struct PermissionWarningView: View {
    let message: LocalizedStringResource
    let actionTitle: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            WarningLabel(message: message)
            Button(actionTitle, action: action)
                .buttonStyle(.link)
                .font(.callout)
        }
        // A preferred reading width keeps this note from dictating the Form's width;
        // maxWidth lets it fill and wrap to whatever the surrounding controls set.
        .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Screen Recording") {
    PermissionWarningView(
        message: .permissionWarningText,
        actionTitle: .openSystemSettingsToGrant,
        action: { }
    )
}

#Preview("Direct Capture") {
    PermissionWarningView(
        message: .directCaptureWarningText,
        actionTitle: .directCaptureConfirmAction,
        action: { }
    )
}
