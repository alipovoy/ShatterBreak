import SwiftUI

/// Three tabs, each short enough to fit a 13" display without scrolling.
struct PreferencesView: View {
    @Environment(\.permissions) private var permissions

    /// Durations are edited through the model, which reads them once: an `@AppStorage`
    /// binding would desync from the menu.
    @Bindable var state: TimerState

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        // Only the selected tab renders: TabView measures every tab to size itself, so
        // populated hidden tabs would fix the window at the tallest one's height.
        TabView(selection: $selectedTab) {
            Tab(value: SettingsTab.general) {
                if selectedTab == .general {
                    GeneralSettingsTab(state: state)
                }
            } label: {
                Label { Text(.settingsTabGeneral) } icon: { Image(systemName: "gearshape") }
            }

            Tab(value: SettingsTab.schedule) {
                if selectedTab == .schedule {
                    ScheduleSettingsTab(state: state)
                }
            } label: {
                Label { Text(.settingsTabSchedule) } icon: { Image(systemName: "clock") }
            }

            Tab(value: SettingsTab.breakScreen) {
                if selectedTab == .breakScreen {
                    BreakScreenSettingsTab(state: state)
                }
            } label: {
                Label { Text(.settingsTabBreakScreen) } icon: { Image(systemName: "sparkles.rectangle.stack") }
            }
        }
        .frame(width: 480)
        // Hug the selected tab, so the window resizes both ways as the selection changes.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { permissions.refresh() }
    }
}

private enum SettingsTab: Hashable {
    case general
    case schedule
    case breakScreen
}

// MARK: - General

private struct GeneralSettingsTab: View {
    let state: TimerState

    @AppStorage(PreferenceKeys.autoStartOnLaunch)
    private var autoStartOnLaunch = PreferenceDefaults.autoStartOnLaunch
    @AppStorage(PreferenceKeys.menuBarTimerStyle)
    private var menuBarTimerStyle = PreferenceDefaults.menuBarTimerStyle
    @AppStorage(PreferenceKeys.trackStatistics)
    private var trackStatistics = PreferenceDefaults.trackStatistics
    @AppStorage(PreferenceKeys.resetStatisticsOnStart)
    private var resetStatisticsOnStart = PreferenceDefaults.resetStatisticsOnStart
    @AppStorage(PreferenceKeys.countSessionEarly)
    private var countSessionEarly = PreferenceDefaults.countSessionEarly
    @AppStorage(PreferenceKeys.sessionLeadSecs)
    private var sessionLeadSecs = PreferenceDefaults.sessionLeadSecs

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
                // These and the lead controls re-arm the running session's credit point.
                Toggle(.trackStatisticsToggle, isOn: $trackStatistics)
                    .help(Text(.trackStatisticsHelp))
                    .onChange(of: trackStatistics) { state.reconcile() }

                if trackStatistics {
                    Toggle(.resetStatisticsOnStartToggle, isOn: $resetStatisticsOnStart)
                        .help(Text(.resetStatisticsOnStartHelp))

                    Toggle(.countSessionEarlyToggle, isOn: $countSessionEarly)
                        .help(Text(.countSessionEarlyHelp))
                        .onChange(of: countSessionEarly) { state.reconcile() }

                    if countSessionEarly {
                        DurationFieldView(
                            title: .sessionLeadLabel,
                            value: $sessionLeadSecs,
                            min: DurationBounds.minimumSecs,
                            max: DurationBounds.sessionLeadMaximumSecs
                        )
                        .help(Text(.sessionLeadHelp))
                        .onChange(of: sessionLeadSecs) { state.reconcile() }

                        // Not `>`: a lead equal to the work duration already counts the
                        // session at the first tick after Start.
                        if sessionLeadSecs >= state.workDurationSecs {
                            WarningLabel(message: .sessionLeadExceedsWorkWarning)
                                .readingWidth()
                        }
                    }
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
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(breakTimingWarnings, id: \.self) { warning in
                            WarningLabel(message: warning.message)
                        }
                    }
                    .readingWidth()
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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var trial: BreakEffectTrial

    init(state: TimerState) {
        _trial = State(initialValue: BreakEffectTrial(timer: state))
    }

    @AppStorage(PreferenceKeys.effectType) private var effectType = PreferenceDefaults.effectType
    @AppStorage(PreferenceKeys.softOverlay) private var softOverlay = PreferenceDefaults.softOverlay
    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound
    @AppStorage(PreferenceKeys.reduceMotion) private var reduceMotion = PreferenceDefaults.reduceMotion

    var body: some View {
        Form {
            Section(.effectTypePicker) {
                EffectCardPicker(selection: $effectType)
                    .onChange(of: effectType) { _, newValue in
                        guard newValue.requiresScreenCapture else { return }
                        guard permissions.hasScreenRecordingAccess else {
                            // Choosing Shatter is itself the request.
                            permissions.requestAccessIfNeeded()
                            return
                        }

                        // Re-choosing Shatter clears a remembered decline.
                        guard permissions.directCaptureAccess == .refused else { return }
                        confirmDirectCapture()
                    }

                // Screen Recording gates direct capture, so it is raised first.
                if effectType.requiresScreenCapture {
                    if permissions.hasScreenRecordingAccess == false {
                        WarningLabel(
                            message: .permissionWarningText,
                            actionTitle: .openSystemSettingsToGrant,
                            action: grantScreenRecording
                        )
                        .readingWidth()
                    } else if permissions.directCaptureAccess == .refused {
                        WarningLabel(
                            message: .directCaptureWarningText,
                            actionTitle: .directCaptureConfirmAction,
                            action: confirmDirectCapture
                        )
                        .readingWidth()
                    } else {
                        Text(.directCaptureNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .readingWidth()
                    }
                }

                // Left enabled under macOS Reduce Motion: a forced check would report a choice
                // the user never made.
                if effectType.requiresScreenCapture, permissions.isCaptureBlocked == false {
                    Toggle(isOn: $reduceMotion) {
                        Text(.reduceMotionToggle)
                        if accessibilityReduceMotion {
                            Text(.reduceMotionFollowsSystemCaption)
                        }
                    }
                    .help(Text(.reduceMotionHelp))
                }

                Button(.tryEffect) { Task { await trial.start() } }
                    .help(Text(.tryEffectHelp))
                    .disabled(trial.canStart == false)
            }

            Section {
                Toggle(.softOverlayToggle, isOn: $softOverlay)
                Toggle(.playSoundToggle, isOn: $playSound)
            }
        }
        .settingsTabLayout()
    }

    /// Asks and opens System Settings: the app cannot tell whether macOS still holds an answer,
    /// and Settings lists the app only once it has asked.
    private func grantScreenRecording() {
        permissions.requestAccessIfNeeded()
        permissions.openSystemSettings()
    }

    private func confirmDirectCapture() {
        Task { await permissions.confirmDirectCaptureAccess() }
    }
}

// MARK: - Shared tab chrome

private extension View {
    func settingsTabLayout() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("General with an oversized lead") { @MainActor in
    let defaults = UserDefaults.preview("sessionLead")
    defaults.set(true, forKey: PreferenceKeys.trackStatistics)
    defaults.set(true, forKey: PreferenceKeys.countSessionEarly)
    defaults.set(600, forKey: PreferenceKeys.sessionLeadSecs)
    defaults.set(300, forKey: PreferenceKeys.workDurationSecs)

    return GeneralSettingsTab(state: TimerState.parked(.idle(at: .now), defaults: defaults))
        .defaultAppStorage(defaults)
        .frame(width: 480)
}

#Preview("Settings") { @MainActor in
    let defaults = UserDefaults.preview("settings")

    return PreferencesView(state: TimerState.parked(.idle(at: .now), defaults: defaults))
        .environment(\.permissions, ScreenCapturePermissionManager(defaults: defaults))
        .defaultAppStorage(defaults)
}

#Preview("Schedule with warnings") { @MainActor in
    let defaults = UserDefaults.preview("warnings")
    defaults.set(300, forKey: PreferenceKeys.restDurationSecs)
    defaults.set(true, forKey: PreferenceKeys.allowPostpone)
    defaults.set(600, forKey: PreferenceKeys.postponeWindowSecs)
    defaults.set(true, forKey: PreferenceKeys.allowEarlyReturn)
    defaults.set(600, forKey: PreferenceKeys.earlyReturnLeadSecs)

    return ScheduleSettingsTab(state: TimerState.parked(.idle(at: .now), defaults: defaults))
        .defaultAppStorage(defaults)
        .frame(width: 480)
}

#Preview("Break Screen") { @MainActor in
    let defaults = UserDefaults.preview("breakScreen")

    return BreakScreenSettingsTab(state: TimerState.parked(.idle(at: .now), defaults: defaults))
        .environment(\.permissions, ScreenCapturePermissionManager(defaults: defaults))
        .defaultAppStorage(defaults)
        .frame(width: 480)
}
