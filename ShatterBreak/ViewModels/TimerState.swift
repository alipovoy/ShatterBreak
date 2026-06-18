// swiftlint:disable file_length
// swiftlint:disable type_body_length
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
    var timeRemaining: TimeInterval {
        get {
            currentRemainingTime(at: tickSource.now)
        }
        set {
            let clampedValue = max(0, newValue)
            frozenTimeRemaining = clampedValue

            guard activeDeadline != nil else { return }
            activeDeadline = tickSource.now.addingTimeInterval(clampedValue)
            startCountdownMonitoring()
        }
    }

    var shouldShowTimeInMenuBar: Bool {
        switch mode {
        case .running, .paused, .postponedWork:
            return true
        default:
            return false
        }
    }

    var formattedTimeRemaining: String {
        formattedTimeRemaining(at: tickSource.now)
    }

    // MARK: - Private State

    private var activeDeadline: Date?
    private var frozenTimeRemaining: TimeInterval = 0
    private var savedRestRemaining: TimeInterval?
    private var isSystemAsleep = false
    private var modeBeforePause: Mode?
    private var wasAutoPausedBySystem = false
    private var modeBeforeSleep: Mode?

    private var expiryTask: Task<Void, Never>?
    private var sleepObserverTokens: [any NSObjectProtocol] = []

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
        stopCountdownMonitoring()
        activeDeadline = nil
        deactivateSleepObservers()
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
            // `start()` dismisses the overlays because `mode` is still `.resting`.
            clearCountdown()
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
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlayManager.dismissOverlays()
        deactivateSleepObservers()
    }

    func postpone() {
        guard mode == .resting && !hasPostponeBeenUsedThisCycle else { return }

        let remainingRest = timeRemaining
        freezeCountdown()
        savedRestRemaining = remainingRest
        mode = .postponedWork
        hasPostponeBeenUsedThisCycle = true
        overlayManager.dismissOverlays()
        beginCountdown(for: postponeDurationSecs)
    }

    // MARK: - Timer Control

    func timeRemaining(at referenceDate: Date) -> TimeInterval {
        currentRemainingTime(at: referenceDate)
    }

    func formattedTimeRemaining(at referenceDate: Date) -> String {
        Self.format(timeInterval: timeRemaining(at: referenceDate))
    }

    private func beginCountdown(for duration: TimeInterval) {
        let clampedDuration = max(0, duration)
        activateSleepObserversIfNeeded()
        frozenTimeRemaining = clampedDuration
        activeDeadline = tickSource.now.addingTimeInterval(clampedDuration)
        startCountdownMonitoring()
        handleCountdownExpiryIfNeeded()
    }

    private func resumeCountdown() {
        beginCountdown(for: timeRemaining)
    }

    private func freezeCountdown() {
        frozenTimeRemaining = currentRemainingTime(at: tickSource.now)
        stopCountdownMonitoring()
        activeDeadline = nil
    }

    private func currentRemainingTime(at referenceDate: Date) -> TimeInterval {
        guard let activeDeadline, isRunning else { return frozenTimeRemaining }
        return max(0, activeDeadline.timeIntervalSince(referenceDate))
    }

    private func clearCountdown() {
        frozenTimeRemaining = 0
        stopCountdownMonitoring()
        activeDeadline = nil
    }

    private func stopCountdownMonitoring() {
        expiryTask?.cancel()
        expiryTask = nil
        tickSource.stop()
    }

    private func handleCountdownExpiryIfNeeded() {
        guard currentRemainingTime(at: tickSource.now) <= 0 else { return }

        switch mode {
        case .postponedWork:
            clearCountdown()
            resumeRest()
        case .resting:
            guard isSystemAsleep == false else { return }

            clearCountdown()

            if autoStartWorkTimer {
                // `start()` dismisses the overlays because `mode` is still `.resting`.
                start()
            } else {
                mode = .awaitingReturn
                deactivateSleepObservers()
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

    private func activateSleepObserversIfNeeded() {
        guard sleepObserverTokens.isEmpty else { return }

        let notifications: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]

        // Register synchronously with the block-based API so the observers are
        // guaranteed to be subscribed by the time this method returns. The async
        // `notifications(named:)` sequence subscribed lazily inside a spawned Task,
        // which raced with notifications posted right after `start()` and could drop
        // them (NotificationCenter does not buffer for a not-yet-subscribed consumer).
        // `NSWorkspace` sleep/wake notifications are delivered on the main thread, so a
        // `nil` queue runs the block synchronously on the main actor.
        for name in notifications {
            let token = workspaceNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleNotification(name)
                }
            }
            sleepObserverTokens.append(token)
        }
    }

    private func deactivateSleepObservers() {
        sleepObserverTokens.forEach { workspaceNotificationCenter.removeObserver($0) }
        sleepObserverTokens.removeAll()
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
            if currentRemainingTime(at: tickSource.now) <= 0 {
                clearCountdown()
                mode = .idle
                overlayManager.dismissOverlays()
                deactivateSleepObservers()
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

    private func startCountdownMonitoring() {
        stopCountdownMonitoring()

        if tickSource.usesManualTicks {
            tickSource.start { [weak self] in
                self?.handleCountdownExpiryIfNeeded()
            }
            return
        }

        guard let activeDeadline else { return }

        let sleepDuration = max(0, activeDeadline.timeIntervalSinceNow)
        expiryTask = Task(priority: .utility) { [weak self] in
            do {
                if sleepDuration > 0 {
                    try await Task.sleep(
                        for: .seconds(sleepDuration),
                        tolerance: .milliseconds(200)
                    )
                }
                try Task.checkCancellation()
            } catch {
                return
            }

            self?.handleExpiryTask(for: activeDeadline)
        }
    }

    private func handleExpiryTask(for deadline: Date) {
        guard activeDeadline == deadline else { return }
        handleCountdownExpiryIfNeeded()
    }

    // MARK: - Formatting

    nonisolated static func format(timeInterval interval: TimeInterval) -> String {
        let displayInterval = Int(ceil(max(0, interval)))
        let minutes = displayInterval / 60
        let seconds = displayInterval % 60
        let minutesStr = minutes.formatted(.number.precision(.integerLength(2...2)))
        let secondsStr = seconds.formatted(.number.precision(.integerLength(2...2)))
        return "\(minutesStr):\(secondsStr)"
    }
}
// swiftlint:enable type_body_length
