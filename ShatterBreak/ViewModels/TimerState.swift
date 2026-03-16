import SwiftUI

/// Manages the timer state machine for work/rest cycles with postpone capability.
@MainActor
@Observable
final class TimerState {
    // MARK: - Types
    
    /// Represents the current operational state of the timer.
    enum Mode: Equatable {
        case idle           // No active timer
        case running        // Counting down work period
        case paused         // Work paused (user or system initiated)
        case resting        // Counting down rest period
        case postponedWork  // Postponed rest, counting down work period
        case awaitingReturn // Manual mode: rest complete, waiting for user
    }
    
    // MARK: - Properties
    
    /// The current operational mode. All boolean state flags derive from this.
    var mode: Mode = .idle
    
    var workDurationSecs: Double {
        didSet { defaults.set(workDurationSecs, forKey: PreferenceKeys.workDurationSecs) }
    }
    
    var restDurationSecs: Double {
        didSet { defaults.set(restDurationSecs, forKey: PreferenceKeys.restDurationSecs) }
    }
    
    var postponeDurationSecs: Double = 60
    
    /// Whether postpone is available: only when resting and not yet used this cycle.
    var canPostpone: Bool {
        mode == .resting && !hasPostponeBeenUsedThisCycle
    }
    
    /// Whether the timer is actively counting down (work, rest, or postponed work).
    var isRunning: Bool {
        mode == .running || mode == .resting || mode == .postponedWork
    }
    
    var isPaused: Bool { mode == .paused }
    var isResting: Bool { mode == .resting }
    var awaitingReturn: Bool { mode == .awaitingReturn }
    var canEditDurations: Bool { mode == .idle }
    
    var hasPostponeBeenUsedThisCycle = false
    var timeRemaining: TimeInterval = 0
    
    var shouldShowTimeInMenuBar: Bool {
        switch mode {
        case .running, .paused, .postponedWork:
            return true
        default:
            return false
        }
    }
    
    var formattedTimeRemaining: String {
        TimerState.format(timeInterval: timeRemaining)
    }
    
    // MARK: - Private State
    
    private var activeDeadline: Date?
    private var savedRestRemaining: TimeInterval?
    private var isSystemAsleep = false
    private var modeBeforePause: Mode?
    private var wasAutoPausedBySystem = false
    private var modeBeforeSleep: Mode?
    
    private var sleepObserverTasks: [Task<Void, Never>] = []
    
    private let overlayManager: any OverlayManaging
    private let defaults: UserDefaults
    private let tickSource: any TimerTickSource
    private let workspaceNotificationCenter: NotificationCenter
    
    private var autoStartWorkTimer: Bool {
        defaults.string(forKey: PreferenceKeys.workStartMode)
            .flatMap { WorkStartMode(rawValue: $0) } ?? .automatic == .automatic
    }
    
    // MARK: - Initialization
    
    init(
        overlayManager: any OverlayManaging,
        postponeDurationSecs: Double = 60,
        defaults: UserDefaults = .standard,
        tickSource: (any TimerTickSource)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.overlayManager = overlayManager
        self.postponeDurationSecs = postponeDurationSecs
        self.defaults = defaults
        self.tickSource = tickSource ?? SystemTimerTickSource()
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.workDurationSecs = Self.loadDuration(
            forKey: PreferenceKeys.workDurationSecs, defaultValue: 1500, defaults: defaults)
        self.restDurationSecs = Self.loadDuration(
            forKey: PreferenceKeys.restDurationSecs, defaultValue: 300, defaults: defaults)
        setupSleepObservers()
    }
    
    convenience init(
        postponeDurationSecs: Double = 60,
        defaults: UserDefaults = .standard,
        tickSource: (any TimerTickSource)? = nil,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.init(
            overlayManager: OverlayManager(),
            postponeDurationSecs: postponeDurationSecs,
            defaults: defaults,
            tickSource: tickSource,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    isolated deinit {
        tickSource.stop()
        sleepObserverTasks.forEach { $0.cancel() }
    }
    
    private static func loadDuration(
        forKey key: String,
        defaultValue: Double,
        defaults: UserDefaults
    ) -> Double {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : defaultValue
    }
    
    // MARK: - User Actions
    
    func start() {
        if mode == .resting || mode == .awaitingReturn {
            overlayManager.dismissOverlays()
        }
        
        mode = .running
        modeBeforePause = nil
        wasAutoPausedBySystem = false
        beginCountdown(for: workDurationSecs)
    }
    
    func pause() {
        switch mode {
        case .running, .postponedWork:
            let previousMode = mode
            freezeCountdown()
            modeBeforePause = previousMode
            mode = .paused
            wasAutoPausedBySystem = false
        case .resting:
            clearCountdown()
            overlayManager.dismissOverlays()
            start()
        case .idle, .paused, .awaitingReturn:
            return
        }
    }
    
    func resume() {
        guard mode == .paused else { return }

        let resumedMode = modeBeforePause ?? .running
        modeBeforePause = nil
        mode = resumedMode
        resumeCountdown()
    }
    
    func stop() {
        clearCountdown()
        mode = .idle
        modeBeforePause = nil
        wasAutoPausedBySystem = false
        timeRemaining = 0
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlayManager.dismissOverlays()
    }
    
    func postpone() {
        guard mode == .resting && !hasPostponeBeenUsedThisCycle else { return }
        
        freezeCountdown()
        savedRestRemaining = timeRemaining
        mode = .postponedWork
        hasPostponeBeenUsedThisCycle = true
        overlayManager.dismissOverlays()
        beginCountdown(for: postponeDurationSecs)
    }
    
    // MARK: - Timer Control
    
    private func runTimer() {
        tickSource.start { [weak self] in
            self?.tick()
        }
    }
    
    private func tick() {
        switch mode {
        case .running, .resting, .postponedWork:
            refreshCountdown()
            handleCountdownExpiryIfNeeded()
        case .idle, .paused, .awaitingReturn:
            return
        }
    }
    
    private func beginCountdown(for duration: TimeInterval) {
        let clampedDuration = max(0, duration)
        timeRemaining = clampedDuration
        activeDeadline = tickSource.now.addingTimeInterval(clampedDuration)
        runTimer()
    }
    
    private func resumeCountdown() {
        beginCountdown(for: timeRemaining)
    }
    
    private func freezeCountdown() {
        refreshCountdown()
        clearCountdown()
    }
    
    private func refreshCountdown() {
        guard let activeDeadline else { return }
        timeRemaining = max(0, activeDeadline.timeIntervalSince(tickSource.now))
    }
    
    private func clearCountdown() {
        tickSource.stop()
        activeDeadline = nil
    }
    
    private func handleCountdownExpiryIfNeeded() {
        guard timeRemaining <= 0 else { return }
        
        switch mode {
        case .postponedWork:
            clearCountdown()
            resumeRest()
        case .resting:
            guard isSystemAsleep == false else { return }
            
            clearCountdown()
            
            if autoStartWorkTimer {
                overlayManager.dismissOverlays()
                start()
            } else {
                mode = .awaitingReturn
                timeRemaining = 0
                // Overlay remains visible for user to click "I'm back"
            }
        case .running:
            clearCountdown()
            enterRestPhase()
        case .idle, .paused, .awaitingReturn:
            break
        }
    }
    
    // MARK: - Phase Transitions
    
    private func enterRestPhase() {
        mode = .resting
        modeBeforePause = nil
        hasPostponeBeenUsedThisCycle = false
        savedRestRemaining = nil
        overlayManager.showOverlays(state: self)
        beginCountdown(for: restDurationSecs)
    }
    
    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }
        
        mode = .resting
        modeBeforePause = nil
        savedRestRemaining = nil
        overlayManager.showOverlays(state: self)
        beginCountdown(for: saved)
    }
    
    // MARK: - Sleep/Wake Handling
    
    private func setupSleepObservers() {
        let notifications: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]
        
        for name in notifications {
            sleepObserverTasks.append(Task { [weak self] in
                guard let self else { return }
                for await _ in workspaceNotificationCenter.notifications(named: name) {
                    self.handleNotification(name)
                }
            })
        }
    }
    
    private func handleNotification(_ name: NSNotification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification:
            handleSleep()
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification:
            handleWake()
        default: break
        }
    }
    
    private func handleSleep() {
        isSystemAsleep = true
        
        guard mode == .running || mode == .postponedWork else { return }
        
        freezeCountdown()
        modeBeforeSleep = mode
        mode = .paused
        wasAutoPausedBySystem = true
    }
    
    private func handleWake() {
        isSystemAsleep = false
        
        if mode == .resting {
            refreshCountdown()
            
            if timeRemaining <= 0 {
                clearCountdown()
                mode = .idle
                overlayManager.dismissOverlays()
            }
            
            return
        }
        
        // Resume if auto-paused by system during work or postponed work
        guard wasAutoPausedBySystem else { return }
        
        wasAutoPausedBySystem = false
        mode = (modeBeforeSleep == .postponedWork) ? .postponedWork : .running
        modeBeforeSleep = nil
        resumeCountdown()
    }
    
    // MARK: - Formatting
    
    nonisolated static func format(timeInterval interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        let minutesStr = minutes.formatted(.number.precision(.integerLength(2...2)))
        let secondsStr = seconds.formatted(.number.precision(.integerLength(2...2)))
        return "\(minutesStr):\(secondsStr)"
    }
}
