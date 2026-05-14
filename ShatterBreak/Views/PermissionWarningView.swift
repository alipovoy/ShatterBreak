import SwiftUI

struct PermissionWarningView: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Shatter requires Screen Recording permission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Open System Settings to grant permission", action: onOpenSystemSettings)
                .buttonStyle(.link)
                .font(.footnote)
        }
    }
}

#Preview("Permission Warning") {
    PermissionWarningView(onOpenSystemSettings: { })
}
