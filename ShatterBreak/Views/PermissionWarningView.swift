import SwiftUI

/// An inline caution about a missing screen-capture consent, above the ways out of it.
///
/// Shared by both consents the Shatter effect depends on — classic Screen Recording and
/// macOS's separate ``DirectCaptureAccess`` — so every consent note reads identically.
/// The actions are a builder rather than a fixed pair because the two cases differ: a
/// missing Screen Recording grant has exactly one remedy (System Settings), while a
/// declined direct-capture confirmation has two, since accepting the ``EffectType/fogged``
/// fallback for good is a legitimate answer.
struct PermissionWarningView<Actions: View>: View {
    let message: LocalizedStringResource
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading) {
            WarningLabel(message: message)
            HStack {
                actions
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        // A preferred reading width keeps this note from dictating the Form's width;
        // maxWidth lets it fill and wrap to whatever the surrounding controls set.
        .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Screen Recording") {
    PermissionWarningView(message: .permissionWarningText) {
        Button(.openSystemSettings) { }
        Button(.useFoggedEffectAction) { }
    }
}

#Preview("Direct Capture") {
    PermissionWarningView(message: .directCaptureWarningText) {
        Button(.directCaptureConfirmAction) { }
        Button(.useFoggedEffectAction) { }
    }
}
