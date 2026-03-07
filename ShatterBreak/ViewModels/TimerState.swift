import Combine
import SwiftUI

@MainActor
class TimerState: ObservableObject {
    @AppStorage("workDurationSecs") var workDurationSecs: Double = 1500
    @AppStorage("restDurationSecs") var restDurationSecs: Double = 300

    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isResting = false
    @Published var timeRemaining: TimeInterval = 0

    private var timerTask: Task<Void, Never>?
    private var sleepObserverTasks = [Task<Void, Never>]()
    private let overlayManager: any OverlayManaging

    // Set when rest begins; wall-clock source of truth for rest countdown.
    private var restStartedAt: Date?

    // Set when the system signals imminent sleep; cleared on any wake event.
    // Prevents tick() from auto-starting work before handleWake() can apply R2.
    private var isSystemAsleep = false

    // True when the system auto-paused the work timer so we can auto-resume on wake.
    private var wasAutoPausedBySystem = false

    init(overlayManager: any OverlayManaging) {
        self.overlayManager = overlayManager
        setupSleepObservers()
    }

    convenience init() {
        self.init(overlayManager: OverlayManager())
    }

    // MARK: - Public API

    func start() {
        timeRemaining = workDurationSecs
        isRunning = true
        isPaused = false
        wasAutoPausedBySystem = false
        runTimer()
    }

    func pause() {
        if isResting {
            // "Skip Rest": cancel rest and start work immediately.
            timerTask?.cancel()
            restStartedAt = nil
            isResting = false
            overlayManager.dismissOverlays()
            start()
        } else {
            isPaused = true
            timerTask?.cancel()
        }
    }

    func resume() {
        isPaused = false
        runTimer()
    }

    func stop() {
        timerTask?.cancel()
        isRunning = false
        isPaused = false
        isResting = false
        wasAutoPausedBySystem = false
        timeRemaining = 0
        restStartedAt = nil
        overlayManager.dismissOverlays()
    }

    // MARK: - Timer

    private func runTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }

    private func tick() {
        if isResting, let anchor = restStartedAt {
            // Rest phase: wall-clock is source of truth.
            timeRemaining = max(0, restDurationSecs - Date().timeIntervalSince(anchor))

            if timeRemaining <= 0 && !isSystemAsleep {
                // Rest complete while user is present — auto-start next work session.
                timerTask?.cancel()
                restStartedAt = nil
                isResting = false
                overlayManager.dismissOverlays()
                start()
            }
        } else {
            // Work phase: tick-based (machine is awake, user is working).
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                triggerRestPhase()
            }
        }
    }

    private func triggerRestPhase() {
        isResting = true
        restStartedAt = Date()
        timeRemaining = restDurationSecs
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    // MARK: - Sleep & Display Observation

    private func setupSleepObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        sleepObserverTasks.append(
            Task { @MainActor [weak self] in
                for await _ in nc.notifications(named: NSWorkspace.willSleepNotification) {
                    self?.handleSleep()
                }
            })

        sleepObserverTasks.append(
            Task { @MainActor [weak self] in
                for await _ in nc.notifications(named: NSWorkspace.screensDidSleepNotification) {
                    self?.handleDisplaySleep()
                }
            })

        sleepObserverTasks.append(
            Task { @MainActor [weak self] in
                for await _ in nc.notifications(named: NSWorkspace.didWakeNotification) {
                    self?.handleWake()
                }
            })

        sleepObserverTasks.append(
            Task { @MainActor [weak self] in
                for await _ in nc.notifications(named: NSWorkspace.screensDidWakeNotification) {
                    self?.handleWake()
                }
            })
    }

    private func handleSleep() {
        isSystemAsleep = true
        // Work phase only: pause the tick-based timer.
        // Rest phase: wall-clock anchor keeps running — no action needed.
        guard isRunning && !isPaused && !isResting else { return }
        pause()
        wasAutoPausedBySystem = true
    }

    // Display sleep only (screensaver / display timeout).
    // Machine RunLoop keeps running, so no isSystemAsleep flag needed.
    private func handleDisplaySleep() {
        guard isRunning && !isPaused && !isResting else { return }
        pause()
        wasAutoPausedBySystem = true
    }

    private func handleWake() {
        // Clear sleep flag first — tick() may fire on the same RunLoop cycle.
        isSystemAsleep = false

        if isResting, let anchor = restStartedAt {
            // Rest phase: check if rest expired while the user was away.
            let elapsed = Date().timeIntervalSince(anchor)
            if elapsed >= restDurationSecs {
                // R2: rest expired during absence — return to idle, user starts manually.
                timerTask?.cancel()
                restStartedAt = nil
                isResting = false
                isRunning = false
                overlayManager.dismissOverlays()
            }
            // else: rest still has time → tick continues, overlay stays.
        } else if wasAutoPausedBySystem {
            // Work phase: auto-resume after system-initiated pause.
            wasAutoPausedBySystem = false
            resume()
        }
    }
}
