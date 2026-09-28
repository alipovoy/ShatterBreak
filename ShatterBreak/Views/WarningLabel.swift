import SwiftUI

/// Every caution in Preferences: a warning triangle beside wrapping text, above the one
/// action that fixes it, when there is one.
struct WarningLabel: View {
    let message: LocalizedStringResource
    var actionTitle: LocalizedStringResource?
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.orange)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }
}

#Preview("Warnings") {
    Form {
        WarningLabel(message: .windowsOverlapWarning)
        WarningLabel(message: .permissionWarningText, actionTitle: .openSystemSettingsToGrant)
        WarningLabel(message: .directCaptureWarningText, actionTitle: .directCaptureConfirmAction)
    }
    .formStyle(.grouped)
}
