import SwiftUI

/// An inline caution about a missing screen-capture consent, with the one link that
/// resolves it.
///
/// Shared by both consents the Shatter effect depends on — classic Screen Recording and
/// macOS's separate ``DirectCaptureAccess`` — because each is a sentence of explanation
/// above a single recovery action, and they should read identically.
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
