import SwiftUI

/// Everything Preferences says about Shatter's access to the screen — the app's whole voice
/// on the subject, there being no alert of its own in the flow.
///
/// The three states are ordered by what must be fixed first: Screen Recording gates the
/// direct-capture confirmation, so there is no point discussing the second while the first
/// is missing. Missing means missing whether or not the app has asked; a warning hidden
/// until the first request reads as a broken one.
///
/// Each warning carries only the action granting the consent it is about. Neither offers to
/// switch to Fogged: the effect picker sits directly above, so the offer would duplicate a
/// visible control.
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
