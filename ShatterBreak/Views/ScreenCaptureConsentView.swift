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
/// A declined confirmation is remembered across launches, so this warning is the state's
/// only visible trace until the user acts on it — which is why it carries a way out
/// rather than just an explanation.
struct ScreenCaptureConsentView: View {
    let status: ScreenCapturePermissionManager.Status
    let directCaptureAccess: DirectCaptureAccess
    let onOpenSystemSettings: () -> Void
    let onConfirmDirectCapture: () -> Void
    let onUseFoggedEffect: () -> Void

    var body: some View {
        if status == .denied {
            PermissionWarningView(message: .permissionWarningText) {
                Button(.openSystemSettingsToGrant, action: onOpenSystemSettings)
            }
        } else if directCaptureAccess == .refused {
            // Two exits, because both are legitimate answers: ask macOS again, or settle
            // for the fallback the break is already using. Choosing Fogged also ends the
            // asking for good — the probe only runs while Shatter is selected.
            PermissionWarningView(message: .directCaptureWarningText) {
                Button(.directCaptureConfirmAction, action: onConfirmDirectCapture)
                Button(.directCaptureUseFoggedAction, action: onUseFoggedEffect)
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
