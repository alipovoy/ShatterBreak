import SwiftUI

/// An inline caution about a missing screen-capture consent, above the one action that
/// grants it.
///
/// Shared by both consents the Shatter effect depends on — classic Screen Recording and
/// macOS's separate ``DirectCaptureAccess`` — so every consent warning reads identically
/// and differs only in what it says and where it sends the user. Neither offers to switch
/// to the ``EffectType/fogged`` fallback: the effect picker sits directly above, so that
/// would duplicate a visible control while restating the message's own text.
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
