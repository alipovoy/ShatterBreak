import SwiftUI

/// The app's Settings window: three System Settings-style tabs (General, Schedule,
/// Break Screen) that keep each pane short enough to fit a 13" display without
/// scrolling.
struct PreferencesView: View {
    @Environment(\.permissions) private var permissions

    /// The live timer model. Work/Rest durations must be edited through it — it
    /// loads its durations from defaults once at init and persists on set, so a
    /// plain `@AppStorage` binding here would silently desync from the menu.
    @Bindable var state: TimerState

    var body: some View {
        TabView {
            Tab {
                GeneralSettingsTab()
            } label: {
                Label { Text(.settingsTabGeneral) } icon: { Image(systemName: "gearshape") }
            }

            Tab {
                ScheduleSettingsTab(state: state)
            } label: {
                Label { Text(.settingsTabSchedule) } icon: { Image(systemName: "clock") }
            }

            Tab {
                BreakScreenSettingsTab()
            } label: {
                Label { Text(.settingsTabBreakScreen) } icon: { Image(systemName: "sparkles.rectangle.stack") }
            }
        }
        .frame(width: 480)
        .onAppear { permissions.refresh() }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(PreferenceKeys.autoStartOnLaunch)
    private var autoStartOnLaunch = PreferenceDefaults.autoStartOnLaunch
    @AppStorage(PreferenceKeys.menuBarTimerStyle)
    private var menuBarTimerStyle = PreferenceDefaults.menuBarTimerStyle
    @AppStorage(PreferenceKeys.trackStatistics)
    private var trackStatistics = PreferenceDefaults.trackStatistics
    @AppStorage(PreferenceKeys.resetStatisticsOnStart)
    private var resetStatisticsOnStart = PreferenceDefaults.resetStatisticsOnStart

    var body: some View {
        Form {
            Section {
                Toggle(.autoStartOnLaunchToggle, isOn: $autoStartOnLaunch)
                    .help(Text(.autoStartOnLaunchHelp))

                Picker(.showTimerInMenuBarToggle, selection: $menuBarTimerStyle) {
                    ForEach(MenuBarTimerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .help(Text(.showTimerInMenuBarHelp))
            }

            Section(.statistics) {
                Toggle(.trackStatisticsToggle, isOn: $trackStatistics)
                    .help(Text(.trackStatisticsHelp))

                if trackStatistics {
                    Toggle(.resetStatisticsOnStartToggle, isOn: $resetStatisticsOnStart)
                        .help(Text(.resetStatisticsOnStartHelp))
                }
            }
        }
        .settingsTabLayout()
    }
}

// MARK: - Schedule

private struct ScheduleSettingsTab: View {
    @Bindable var state: TimerState

    @AppStorage(PreferenceKeys.workStartMode)
    private var workStartMode = PreferenceDefaults.workStartMode
    @AppStorage(PreferenceKeys.allowPostpone)
    private var allowPostpone = PreferenceDefaults.allowPostpone
    @AppStorage(PreferenceKeys.postponeWindowSecs)
    private var postponeWindowSecs = PreferenceDefaults.postponeWindowSecs
    @AppStorage(PreferenceKeys.postponeDurationSecs)
    private var postponeDurationSecs = PreferenceDefaults.postponeDurationSecs
    @AppStorage(PreferenceKeys.allowEarlyReturn)
    private var allowEarlyReturn = PreferenceDefaults.allowEarlyReturn
    @AppStorage(PreferenceKeys.earlyReturnLeadSecs)
    private var earlyReturnLeadSecs = PreferenceDefaults.earlyReturnLeadSecs

    var body: some View {
        Form {
            Section {
                DurationFieldView(
                    title: .workDuration,
                    value: $state.workDurationSecs,
                    min: DurationBounds.minimumSecs,
                    max: DurationBounds.workMaximumSecs
                )

                DurationFieldView(
                    title: .restDuration,
                    value: $state.restDurationSecs,
                    min: DurationBounds.minimumSecs,
                    max: DurationBounds.restMaximumSecs
                )

                // WorkStartMode has exactly two cases, so it reads better as a
                // toggle than as the picker it is stored as.
                Toggle(.startWorkAutomaticallyToggle, isOn: startWorkAutomatically)
                    .help(Text(.workStartModeHelp))
            }

            Section {
                Toggle(.allowPostponeToggle, isOn: $allowPostpone)

                if allowPostpone {
                    DurationFieldView(
                        title: .postponeWindowLabel,
                        value: $postponeWindowSecs,
                        min: DurationBounds.minimumSecs,
                        max: DurationBounds.postponeWindowMaximumSecs
                    )
                    .help(Text(.postponeWindowHelp))

                    DurationFieldView(
                        title: .postponeDurationLabel,
                        value: $postponeDurationSecs,
                        min: DurationBounds.minimumSecs,
                        max: DurationBounds.postponeDurationMaximumSecs
                    )
                    .help(Text(.postponeDurationHelp))
                }
            }

            Section {
                Toggle(.allowEarlyReturnToggle, isOn: $allowEarlyReturn)
                    .help(Text(.allowEarlyReturnHelp))

                if allowEarlyReturn {
                    DurationFieldView(
                        title: .earlyReturnLeadLabel,
                        value: $earlyReturnLeadSecs,
                        min: DurationBounds.minimumSecs,
                        max: DurationBounds.earlyReturnLeadMaximumSecs
                    )
                    .help(Text(.earlyReturnLeadHelp))
                }
            }

            if breakTimingWarnings.isEmpty == false {
                Section {
                    BreakTimingWarningsView(warnings: breakTimingWarnings)
                }
            }
        }
        .settingsTabLayout()
    }

    private var startWorkAutomatically: Binding<Bool> {
        Binding(
            get: { workStartMode == .automatic },
            set: { workStartMode = $0 ? .automatic : .manual }
        )
    }

    /// The break-timing contradiction warnings for the current settings. Rest is read
    /// from the live model, so the warnings react to edits made here or in the menu.
    private var breakTimingWarnings: [BreakTimingWarning] {
        BreakTimingValidator.warnings(
            restDurationSecs: state.restDurationSecs,
            allowPostpone: allowPostpone,
            postponeWindowSecs: postponeWindowSecs,
            allowEarlyReturn: allowEarlyReturn,
            earlyReturnLeadSecs: earlyReturnLeadSecs
        )
    }
}

// MARK: - Break Screen

private struct BreakScreenSettingsTab: View {
    @Environment(\.permissions) private var permissions

    @AppStorage(PreferenceKeys.effectType) private var effectType = PreferenceDefaults.effectType
    @AppStorage(PreferenceKeys.softOverlay) private var softOverlay = PreferenceDefaults.softOverlay
    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound

    @State private var showPermissionAlert = false

    var body: some View {
        Form {
            Section(.effectTypePicker) {
                EffectCardPicker(selection: $effectType)
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
            }

            Section {
                Toggle(.softOverlayToggle, isOn: $softOverlay)
                Toggle(.playSoundToggle, isOn: $playSound)
            }
        }
        .settingsTabLayout()
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

// MARK: - Shared tab chrome

private extension View {
    /// Grouped, non-scrolling form that hugs its content, so the Settings window
    /// resizes to each tab the way System Settings panes do.
    func settingsTabLayout() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    PreferencesView(state: TimerState())
        .environment(\.permissions, ScreenCapturePermissionManager())
}
