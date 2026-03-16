import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.permissions) private var permissions

    @AppStorage(PreferenceKeys.playSound) private var playSound: Bool = true
    @AppStorage(PreferenceKeys.effectType) private var effectType: EffectType = .shatter
    @AppStorage(PreferenceKeys.softOverlay) private var softOverlay: Bool = true
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone: Bool = false
    @AppStorage(PreferenceKeys.showTimerInMenuBar) private var showTimerInMenuBar: Bool = false
    @AppStorage(PreferenceKeys.workStartMode) private var workStartMode: WorkStartMode = .automatic

    @State private var showPermissionAlert = false

    var body: some View {
        VStack {
            Form {
                Section("General Settings") {
                    Toggle("Play Sound", isOn: $playSound)
                    Toggle("Soft Overlay (allows menu bar access)", isOn: $softOverlay)
                    Toggle("Allow Postpone", isOn: $allowPostpone)

                    Picker("Effect Type", selection: $effectType) {
                        ForEach(EffectType.allCases) { effect in
                            Text(effect.displayName).tag(effect)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: effectType) { oldValue, newValue in
                        guard newValue == .shatter else { return }
                        guard permissions.status != .granted else { return }
                        showPermissionAlert = true
                    }

                    if permissions.status == .denied {
                        permissionWarning
                    }

                    // Menu bar display preference
                    Picker("Start work after break ends", selection: $workStartMode) {
                        ForEach(WorkStartMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .help("Choose whether the work timer should automatically start when your rest finishes or wait until you press a button.")

                    Toggle("Show timer in menu bar", isOn: $showTimerInMenuBar)
                        .help("When enabled, the remaining time will be shown next to the app icon in the menu bar.")
                }
                .headerProminence(.increased)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .fixedSize()
        .onAppear { permissions.refresh() }
        .alert("Screen Recording Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Settings") {
                permissions.openSystemSettings()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Shatter requires Screen Recording permission. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording.")
        }
    }

    @ViewBuilder
    private var permissionWarning: some View {
        VStack(alignment: .leading) {
            HStack {
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

#Preview {
    PreferencesView()
        .environment(\.permissions, ScreenCapturePermissionManager())
}
