import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.permissions) private var permissions

    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound
    @AppStorage(PreferenceKeys.effectType) private var effectType = PreferenceDefaults.effectType
    @AppStorage(PreferenceKeys.crackStyle) private var crackStyle = PreferenceDefaults.crackStyle
    @AppStorage(PreferenceKeys.softOverlay) private var softOverlay = PreferenceDefaults.softOverlay
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone = PreferenceDefaults.allowPostpone
    @AppStorage(PreferenceKeys.showTimerInMenuBar)
    private var showTimerInMenuBar = PreferenceDefaults.showTimerInMenuBar
    @AppStorage(PreferenceKeys.workStartMode) private var workStartMode = PreferenceDefaults.workStartMode

    @State private var showPermissionAlert = false

    private let buildHash = AppInfo.current.commitHash

    var body: some View {
        VStack {
            Form {
                Section(.generalSettings) {
                    Toggle(.playSoundToggle, isOn: $playSound)
                    Toggle(.softOverlayToggle, isOn: $softOverlay)
                    Toggle(.allowPostponeToggle, isOn: $allowPostpone)

                    Picker(.effectTypePicker, selection: $effectType) {
                        ForEach(EffectType.allCases) { effect in
                            Text(effect.displayName).tag(effect)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: effectType) { _, newValue in
                        guard newValue == .shatter else { return }
                        guard permissions.status != .granted else { return }
                        showPermissionAlert = true
                    }

                    // Temporary: lets the cracked-glass highlight styles be compared
                    // in a real break. Collapses to the chosen style once picked.
                    if effectType == .shatter {
                        Picker(selection: $crackStyle) {
                            ForEach(CrackStyle.allCases) { style in
                                Text(verbatim: style.label).tag(style)
                            }
                        } label: {
                            Text(verbatim: "Crack style")
                        }
                        .pickerStyle(.radioGroup)
                    }

                    if permissions.status == .denied {
                        PermissionWarningView(onOpenSystemSettings: openSystemSettings)
                    }

                    // Menu bar display preference
                    Picker(.startWorkAfterBreakEnds, selection: $workStartMode) {
                        ForEach(WorkStartMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .help(Text(.workStartModeHelp))

                    Toggle(.showTimerInMenuBarToggle, isOn: $showTimerInMenuBar)
                        .help(Text(.showTimerInMenuBarHelp))
                }
                .headerProminence(.increased)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(buildHash)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(.close) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .fixedSize()
        .onAppear { permissions.refresh() }
        .alert(Text(.permissionAlertTitle), isPresented: $showPermissionAlert) {
            Button(.openSystemSettings, action: openSystemSettings)
            Button(.later, role: .cancel) { }
        } message: {
            Text(.permissionAlertMessage)
        }
    }

    private func openSystemSettings() {
        permissions.openSystemSettings()
    }
}

#Preview {
    PreferencesView()
        .environment(\.permissions, ScreenCapturePermissionManager())
}
