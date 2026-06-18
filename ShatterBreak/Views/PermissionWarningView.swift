import SwiftUI

struct PermissionWarningView: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(.permissionWarningText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(.openSystemSettingsToGrant, action: onOpenSystemSettings)
                .buttonStyle(.link)
                .font(.footnote)
        }
    }
}

#Preview("Permission Warning") {
    PermissionWarningView(onOpenSystemSettings: { })
}
