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
    
    private var savedRestRemaining: TimeInterval?
    private var restStartedAt: Date?
    private var isSystemAsleep = false
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
        timeRemaining = workDurationSecs
        wasAutoPausedBySystem = false
        runTimer()
    }
    
    func pause() {
        if mode == .resting || mode == .postponedWork {
            // Skip rest/postponed work and start fresh work immediately
            tickSource.stop()
            restStartedAt = nil
            overlayManager.dismissOverlays()
            start()
        } else {
            mode = .paused
            tickSource.stop()
        }
    }
    
    func resume() {
        mode = .running
        runTimer()
    }
    
    func stop() {
        tickSource.stop()
        mode = .idle
        wasAutoPausedBySystem = false
        timeRemaining = 0
        restStartedAt = nil
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlayManager.dismissOverlays()
    }
    
    func postpone() {
        guard mode == .resting && !hasPostponeBeenUsedThisCycle else { return }
        
        savedRestRemaining = timeRemaining
        mode = .postponedWork
        hasPostponeBeenUsedThisCycle = true
        timeRemaining = postponeDurationSecs
        overlayManager.dismissOverlays()
    }
    
    // MARK: - Timer Control
    
    private func runTimer() {
        tickSource.start { [weak self] in
            self?.tick()
        }
    }
    
    private func tick() {
        guard mode != .awaitingReturn else { return }
        
        switch mode {
        case .postponedWork:
            tickPostponedWork()
        case .resting:
            tickRest()
        case .running:
            tickWork()
        default:
            break // paused, idle - timer should not be running
        }
    }
    
    private func tickPostponedWork() {
        timeRemaining -= 1
        
        if timeRemaining <= 0 {
            tickSource.stop()
            resumeRest()
        }
    }
    
    private func tickRest() {
        guard let anchor = restStartedAt else { return }
        
        timeRemaining = max(0, restDurationSecs - tickSource.now.timeIntervalSince(anchor))
        
        guard timeRemaining <= 0 && !isSystemAsleep else { return }
        
        tickSource.stop()
        restStartedAt = nil
        
        if autoStartWorkTimer {
            overlayManager.dismissOverlays()
            start()
        } else {
            mode = .awaitingReturn
            timeRemaining = 0
            // Overlay remains visible for user to click "I'm back"
        }
    }
    
    private func tickWork() {
        timeRemaining -= 1
        
        if timeRemaining <= 0 {
            tickSource.stop()
            enterRestPhase()
        }
    }
    
    // MARK: - Phase Transitions
    
    private func enterRestPhase() {
        mode = .resting
        hasPostponeBeenUsedThisCycle = false
        savedRestRemaining = nil
        restStartedAt = tickSource.now
        timeRemaining = restDurationSecs
        overlayManager.showOverlays(state: self)
        runTimer()
    }
    
    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }
        
        mode = .resting
        timeRemaining = saved
        
        // Calculate when rest actually started to maintain accurate remaining time
        let elapsed = restDurationSecs - saved
        restStartedAt = tickSource.now.addingTimeInterval(-elapsed)
        
        savedRestRemaining = nil
        overlayManager.showOverlays(state: self)
        runTimer()
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
        
        modeBeforeSleep = mode
        mode = .paused
        tickSource.stop()
        wasAutoPausedBySystem = true
    }
    
    private func handleWake() {
        isSystemAsleep = false
        
        // If resting, check if rest expired while asleep
        if mode == .resting, let anchor = restStartedAt {
            let elapsed = tickSource.now.timeIntervalSince(anchor)
            guard elapsed >= restDurationSecs && timeRemaining <= 0 else { return }
            
            tickSource.stop()
            restStartedAt = nil
            mode = .idle
            overlayManager.dismissOverlays()
            return
        }
        
        // Resume if auto-paused by system during work or postponed work
        guard wasAutoPausedBySystem else { return }
        
        wasAutoPausedBySystem = false
        mode = (modeBeforeSleep == .postponedWork) ? .postponedWork : .running
        modeBeforeSleep = nil
        runTimer()
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
