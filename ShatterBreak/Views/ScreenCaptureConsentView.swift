import SwiftUI

/// What Preferences says about the Shatter effect's access to the screen — and the app's
/// whole voice on the subject, since there is no alert of its own anywhere in the flow.
///
/// The three states are mutually exclusive and ordered by what must be fixed first: Screen
/// Recording gates the direct-capture confirmation, so there is no point discussing the
/// second while the first is missing. Missing means missing whether or not the app has
/// ever asked — a warning hidden until the first request reads as a broken warning. With
/// both settled, the standing note explains the periodic dialog before it appears.
///
/// Each warning carries one action: the thing that grants the consent it is about. Neither
/// offers to switch to Fogged, even though that is what the break already does — the
/// effect picker sits directly above, so the offer would duplicate a visible control while
/// restating the warning's own text. Every system dialog the app can raise follows an
/// action meaning "I want Shatter to work": pressing Start, picking Shatter, or this link.
struct ScreenCaptureConsentView: View {
    let hasScreenRecordingAccess: Bool
    let directCaptureAccess: DirectCaptureAccess
    let onGrantScreenRecording: () -> Void
    let onConfirmDirectCapture: () -> Void

    var body: some View {
        if hasScreenRecordingAccess == false {
            PermissionWarningView(
                message: .permissionWarningText,
                actionTitle: .openSystemSettingsToGrant,
                action: onGrantScreenRecording
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
                .readingWidth()
        }
    }
}

#Preview("Consent states") {
    Form {
        ScreenCaptureConsentView(
            hasScreenRecordingAccess: true,
            directCaptureAccess: .allowed,
            onGrantScreenRecording: { },
            onConfirmDirectCapture: { }
        )
        ScreenCaptureConsentView(
            hasScreenRecordingAccess: true,
            directCaptureAccess: .refused,
            onGrantScreenRecording: { },
            onConfirmDirectCapture: { }
        )
        ScreenCaptureConsentView(
            hasScreenRecordingAccess: false,
            directCaptureAccess: .unknown,
            onGrantScreenRecording: { },
            onConfirmDirectCapture: { }
        )
    }
    .formStyle(.grouped)
}
