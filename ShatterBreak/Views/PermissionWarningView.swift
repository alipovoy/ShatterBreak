import SwiftUI

struct PermissionWarningView: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            WarningLabel(message: .permissionWarningText)
            Button(.openSystemSettingsToGrant, action: onOpenSystemSettings)
                .buttonStyle(.link)
                .font(.callout)
        }
        // A preferred reading width keeps this note from dictating the Form's width;
        // maxWidth lets it fill and wrap to whatever the surrounding controls set.
        .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Permission Warning") {
    PermissionWarningView(onOpenSystemSettings: { })
}
