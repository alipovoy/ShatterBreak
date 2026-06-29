import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.permissions) private var permissions

    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound
    @AppStorage(PreferenceKeys.effectType) private var effectType = PreferenceDefaults.effectType
    @AppStorage(PreferenceKeys.softOverlay) private var softOverlay = PreferenceDefaults.softOverlay
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone = PreferenceDefaults.allowPostpone
    @AppStorage(PreferenceKeys.showTimerInMenuBar)
    private var showTimerInMenuBar = PreferenceDefaults.showTimerInMenuBar
    @AppStorage(PreferenceKeys.workStartMode) private var workStartMode = PreferenceDefaults.workStartMode
    @AppStorage(PreferenceKeys.autoStartOnLaunch)
    private var autoStartOnLaunch = PreferenceDefaults.autoStartOnLaunch
    @AppStorage(PreferenceKeys.postponeWindowSecs)
    private var postponeWindowSecs = PreferenceDefaults.postponeWindowSecs
    @AppStorage(PreferenceKeys.postponeDurationSecs)
    private var postponeDurationSecs = PreferenceDefaults.postponeDurationSecs
    @AppStorage(PreferenceKeys.allowEarlyReturn)
    private var allowEarlyReturn = PreferenceDefaults.allowEarlyReturn
    @AppStorage(PreferenceKeys.earlyReturnLeadSecs)
    private var earlyReturnLeadSecs = PreferenceDefaults.earlyReturnLeadSecs
    @AppStorage(PreferenceKeys.restDurationSecs)
    private var restDurationSecs = PreferenceDefaults.restDurationSecs

    @State private var showPermissionAlert = false

    private let buildHash = AppInfo.current.commitHash

    /// Break windows top out at 10 minutes, so their MM:SS field needs far less room
    /// than the menu's hour-scale Work/Rest fields.
    private let breakInputWidth: CGFloat = 64

    var body: some View {
        VStack {
            Form {
                Section(.generalSettings) {
                    Toggle(.playSoundToggle, isOn: $playSound)
                    Toggle(.softOverlayToggle, isOn: $softOverlay)
                    Toggle(.allowPostponeToggle, isOn: $allowPostpone)

                    if allowPostpone {
                        DurationSliderView(
                            title: .postponeWindowLabel,
                            systemImage: nil,
                            value: $postponeWindowSecs,
                            min: DurationBounds.minimumSecs,
                            max: DurationBounds.postponeWindowMaximumSecs,
                            inputWidth: breakInputWidth
                        )
                        .help(Text(.postponeWindowHelp))

                        DurationSliderView(
                            title: .postponeDurationLabel,
                            systemImage: nil,
                            value: $postponeDurationSecs,
                            min: DurationBounds.minimumSecs,
                            max: DurationBounds.postponeDurationMaximumSecs,
                            inputWidth: breakInputWidth
                        )
                        .help(Text(.postponeDurationHelp))
                    }

                    Toggle(.allowEarlyReturnToggle, isOn: $allowEarlyReturn)
                        .help(Text(.allowEarlyReturnHelp))

                    if allowEarlyReturn {
                        DurationSliderView(
                            title: .earlyReturnLeadLabel,
                            systemImage: nil,
                            value: $earlyReturnLeadSecs,
                            min: DurationBounds.minimumSecs,
                            max: DurationBounds.earlyReturnLeadMaximumSecs,
                            inputWidth: breakInputWidth
                        )
                        .help(Text(.earlyReturnLeadHelp))
                    }

                    BreakTimingWarningsView(warnings: breakTimingWarnings)

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

                    // Only Shatter needs Screen Recording permission; Fogged and
                    // Dimmed work without it, so the warning is scoped to Shatter.
                    if effectType == .shatter && permissions.status == .denied {
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

                    Toggle(.autoStartOnLaunchToggle, isOn: $autoStartOnLaunch)
                        .help(Text(.autoStartOnLaunchHelp))
                }
                .padding(.horizontal)
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

    /// The break-timing contradiction warnings for the current settings. Recomputes as
    /// any of the inputs change, including Rest edited from the menu (shared key).
    private var breakTimingWarnings: [BreakTimingWarning] {
        BreakTimingValidator.warnings(
            restDurationSecs: restDurationSecs,
            allowPostpone: allowPostpone,
            postponeWindowSecs: postponeWindowSecs,
            allowEarlyReturn: allowEarlyReturn,
            earlyReturnLeadSecs: earlyReturnLeadSecs
        )
    }

    private func openSystemSettings() {
        permissions.openSystemSettings()
    }
}

#Preview {
    PreferencesView()
        .environment(\.permissions, ScreenCapturePermissionManager())
}
