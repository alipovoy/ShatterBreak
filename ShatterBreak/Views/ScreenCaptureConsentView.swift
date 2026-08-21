import SwiftUI

/// What Preferences says about the Shatter effect's access to the screen.
///
/// Shatter depends on two independent consents, and the app used to be able to speak to
/// only one of them: Screen Recording, which `CGPreflightScreenCaptureAccess()` answers.
/// The second — macOS's ``DirectCaptureAccess`` confirmation — was invisible here, so a
/// refusal showed up as a break that quietly stopped freezing the screen (issue #90).
///
/// The three states are mutually exclusive and ordered by what the user must fix first:
/// Screen Recording gates the direct-capture confirmation, so there is no point asking
/// about the second while the first is missing. With both settled, the standing note
/// explains the confirmation the user will keep being asked for, so the system dialog
/// arrives as something the app already mentioned.
///
/// Both warnings offer the same two exits, because both describe the same dead end —
/// Shatter selected, breaks quietly running as Fogged — and in both, settling for that
/// fallback is a legitimate answer rather than a failure to comply. Choosing it also
/// ends the asking for good: nothing requests capture consent unless the selected effect
/// requires it. Only the "grant it" half differs, since the two consents are granted in
/// different places — System Settings for one, a system dialog for the other.
struct ScreenCaptureConsentView: View {
    let status: ScreenCapturePermissionManager.Status
    let directCaptureAccess: DirectCaptureAccess
    let onOpenSystemSettings: () -> Void
    let onConfirmDirectCapture: () -> Void
    let onUseFoggedEffect: () -> Void

    var body: some View {
        if status == .denied {
            PermissionWarningView(message: .permissionWarningText) {
                Button(.openSystemSettings, action: onOpenSystemSettings)
                Button(.useFoggedEffectAction, action: onUseFoggedEffect)
            }
        } else if directCaptureAccess == .refused {
            PermissionWarningView(message: .directCaptureWarningText) {
                Button(.directCaptureConfirmAction, action: onConfirmDirectCapture)
                Button(.useFoggedEffectAction, action: onUseFoggedEffect)
            }
        } else {
            Text(.directCaptureNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Consent states") {
    Form {
        ScreenCaptureConsentView(
            status: .granted,
            directCaptureAccess: .allowed,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { },
            onUseFoggedEffect: { }
        )
        ScreenCaptureConsentView(
            status: .granted,
            directCaptureAccess: .refused,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { },
            onUseFoggedEffect: { }
        )
        ScreenCaptureConsentView(
            status: .denied,
            directCaptureAccess: .unknown,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { },
            onUseFoggedEffect: { }
        )
    }
    .formStyle(.grouped)
}
