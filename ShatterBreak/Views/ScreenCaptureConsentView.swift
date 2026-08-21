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
struct ScreenCaptureConsentView: View {
    let status: ScreenCapturePermissionManager.Status
    let directCaptureAccess: DirectCaptureAccess
    let onOpenSystemSettings: () -> Void
    let onConfirmDirectCapture: () -> Void

    var body: some View {
        if status == .denied {
            PermissionWarningView(
                message: .permissionWarningText,
                actionTitle: .openSystemSettingsToGrant,
                action: onOpenSystemSettings
            )
        } else if directCaptureAccess == .refused {
            PermissionWarningView(
                message: .directCaptureWarningText,
                actionTitle: .directCaptureConfirmAction,
                action: onConfirmDirectCapture
            )
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
            onConfirmDirectCapture: { }
        )
        ScreenCaptureConsentView(
            status: .granted,
            directCaptureAccess: .refused,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { }
        )
        ScreenCaptureConsentView(
            status: .denied,
            directCaptureAccess: .unknown,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { }
        )
    }
    .formStyle(.grouped)
}
