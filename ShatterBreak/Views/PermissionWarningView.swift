import SwiftUI

struct PermissionWarningView: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(.permissionWarningText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(.openSystemSettingsToGrant, action: onOpenSystemSettings)
                .buttonStyle(.link)
                .font(.footnote)
        }
        // A preferred reading width keeps this note from dictating the Form's width;
        // maxWidth lets it fill and wrap to whatever the surrounding controls set.
        .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Permission Warning") {
    PermissionWarningView(onOpenSystemSettings: { })
}
