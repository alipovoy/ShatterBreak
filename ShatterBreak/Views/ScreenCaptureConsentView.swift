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
/// about the second while the first is missing. Missing means missing, whether or not the
/// app has ever asked — a warning that stays hidden until the first request reads as a
/// broken warning. With both settled, the standing note
/// explains the confirmation the user will keep being asked for, so the system dialog
/// arrives as something the app already mentioned.
///
/// Each warning carries exactly one action: the thing that grants the consent it is
/// about. Neither offers to switch to Fogged, even though that is what the break is
/// already doing — the effect picker sits directly above, so the offer would duplicate a
/// control the user is looking at while restating what the warning's own text says.
struct ScreenCaptureConsentView: View {
    let hasScreenRecordingAccess: Bool
    let directCaptureAccess: DirectCaptureAccess
    let onOpenSystemSettings: () -> Void
    let onConfirmDirectCapture: () -> Void

    var body: some View {
        if hasScreenRecordingAccess == false {
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
            hasScreenRecordingAccess: true,
            directCaptureAccess: .allowed,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { }
        )
        ScreenCaptureConsentView(
            hasScreenRecordingAccess: true,
            directCaptureAccess: .refused,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { }
        )
        ScreenCaptureConsentView(
            hasScreenRecordingAccess: false,
            directCaptureAccess: .unknown,
            onOpenSystemSettings: { },
            onConfirmDirectCapture: { }
        )
    }
    .formStyle(.grouped)
}
