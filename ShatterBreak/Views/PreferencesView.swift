import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var permissions: ScreenCapturePermissionManager

    @AppStorage("playSound") private var playSound: Bool = true
    @AppStorage("effectType") private var effectType: EffectType = .shatter

    @State private var showPermissionAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Form {
                Section("General Settings") {
                    Toggle("Play Sound", isOn: $playSound)

                    Picker("Effect Type", selection: $effectType) {
                        ForEach(EffectType.allCases) { effect in
                            Text(effect.rawValue).tag(effect)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: effectType) { _, newValue in
                        // When switching to Shatter without permission: keep the selection
                        // so the user sees their intent reflected, then open the alert
                        // pointing them to System Settings.
                        guard newValue == .shatter else { return }
                        guard permissions.status != .granted else { return }
                        showPermissionAlert = true
                    }

                    // Shown when the system has actively denied permission
                    if permissions.status == .denied {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("Shatter requires Screen Recording permission.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Open System Settings to grant permission") {
                                permissions.openSystemSettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
                .headerProminence(.increased)
            }
            .formStyle(.grouped)
        }
        .onAppear { permissions.refresh() }
        .alert("Screen Recording Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Settings") {
                permissions.openSystemSettings()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Shatter requires Screen Recording permission. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording.")
        }

        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding([.trailing, .bottom])
    }
}

#Preview {
    PreferencesView()
        .environmentObject(ScreenCapturePermissionManager())
}
