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

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        // Each tab's content renders only while selected: TabView measures every
        // tab to size itself, so populated hidden tabs would fix the window at
        // the tallest tab's height with shorter tabs floating centered in it.
        TabView(selection: $selectedTab) {
            Tab(value: SettingsTab.general) {
                if selectedTab == .general {
                    GeneralSettingsTab()
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
        // Hug the selected tab's height so the window opens content-sized and
        // resizes — both ways — when the selection or the tab's content changes.
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
    /// The live timer, consulted for one thing only: a sample must not fight a real break
    /// for the screen.
    let state: TimerState

    @Environment(\.permissions) private var permissions
    @State private var trial = BreakEffectTrial()

    @AppStorage(PreferenceKeys.effectType) private var effectType = PreferenceDefaults.effectType
    @AppStorage(PreferenceKeys.softOverlay) private var softOverlay = PreferenceDefaults.softOverlay
    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound

    var body: some View {
        Form {
            Section(.effectTypePicker) {
                EffectCardPicker(selection: $effectType)
                    .onChange(of: effectType) { _, newValue in
                        guard newValue.requiresScreenCapture else { return }
                        guard permissions.hasScreenRecordingAccess else {
                            // Choosing Shatter is itself the request; the warning below
                            // carries the state whether or not macOS raises a dialog.
                            permissions.requestAccessIfNeeded()
                            return
                        }

                        // Re-choosing Shatter is an explicit "I do want the frozen
                        // screen", so a remembered decline stops standing in the way.
                        guard permissions.directCaptureAccess == .refused else { return }
                        confirmDirectCapture()
                    }

                // Only Shatter captures the screen; Fogged and Dimmed work without
                // any permission, so consent is only ever discussed under Shatter.
                if effectType.requiresScreenCapture {
                    ScreenCaptureConsentView(
                        hasScreenRecordingAccess: permissions.hasScreenRecordingAccess,
                        directCaptureAccess: permissions.directCaptureAccess,
                        onGrantScreenRecording: grantScreenRecording,
                        onConfirmDirectCapture: confirmDirectCapture
                    )
                }

                // The effects are full-screen and low-frequency — a blur radius meant for
                // a display, a fog the window server draws behind the overlay. A card
                // cannot show either, so the picker offers the real thing instead.
                // Centred, because it belongs to the row of cards above it rather than to
                // the form: the cards centre themselves across the row, and a button
                // hugging the form's leading edge reads as a separate, unrelated control.
                Button(.tryEffect) { trial.start() }
                    .help(Text(.tryEffectHelp))
                    .disabled(isBreakOnScreen || trial.isRunning)
                    .frame(maxWidth: .infinity)
            }

            Section {
                Toggle(.softOverlayToggle, isOn: $softOverlay)
                Toggle(.playSoundToggle, isOn: $playSound)
            }
        }
        .settingsTabLayout()
    }

    /// Whether a real break already owns the screen, in which case a sample would be
    /// presenting a second break over the first.
    private var isBreakOnScreen: Bool {
        state.isResting || state.awaitingReturn
    }

    /// Asks *and* opens System Settings, because the app cannot tell which the user needs:
    /// macOS shows its dialog only when it holds no answer, and Settings is the only place
    /// an answer it already holds can be changed. Doing both keeps the link from being a
    /// dead click on a fresh install, where nothing has requested access yet and the app
    /// is therefore not listed in Settings at all.
    private func grantScreenRecording() {
        permissions.requestAccessIfNeeded()
        permissions.openSystemSettings()
    }

    /// Re-opens macOS's direct-capture dialog after the user declined it, so recovery
    /// does not depend on relaunching — System Settings has no switch for this consent.
    private func confirmDirectCapture() {
        Task { await permissions.confirmDirectCaptureAccess() }
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

#Preview("Settings") { @MainActor in
    // `@AppStorage` reads `UserDefaults` and nothing else, so this pane cannot use the
    // in-memory store the other previews do. A suite of its own is the next best thing:
    // toggling a switch in the canvas edits preview state, not real settings.
    let defaults = UserDefaults.preview("settings")

    return PreferencesView(state: TimerState(overlays: .disabled, defaults: defaults))
        .environment(\.permissions, ScreenCapturePermissionManager(defaults: defaults))
        .defaultAppStorage(defaults)
}

#Preview("Schedule with warnings") { @MainActor in
    // Contradictory settings, so the warnings render where they actually appear — under
    // the controls that caused them. On their own they are three lines of orange text
    // about nothing.
    let defaults = UserDefaults.preview("warnings")
    defaults.set(300, forKey: PreferenceKeys.restDurationSecs)
    defaults.set(true, forKey: PreferenceKeys.allowPostpone)
    defaults.set(600, forKey: PreferenceKeys.postponeWindowSecs)
    defaults.set(true, forKey: PreferenceKeys.allowEarlyReturn)
    defaults.set(600, forKey: PreferenceKeys.earlyReturnLeadSecs)

    return ScheduleSettingsTab(state: TimerState(overlays: .disabled, defaults: defaults))
        .defaultAppStorage(defaults)
        .frame(width: 480)
}

#Preview("Break Screen") { @MainActor in
    let defaults = UserDefaults.preview("breakScreen")

    return BreakScreenSettingsTab(state: TimerState(overlays: .disabled, defaults: defaults))
        .environment(\.permissions, ScreenCapturePermissionManager(defaults: defaults))
        .defaultAppStorage(defaults)
        .frame(width: 480)
}
