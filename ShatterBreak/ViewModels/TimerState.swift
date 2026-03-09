import SwiftUI
import Combine

@MainActor
@Observable
final class TimerState {
    var workDurationSecs: Double {
        didSet {
            UserDefaults.standard.set(workDurationSecs, forKey: "workDurationSecs")
        }
    }
    
    var restDurationSecs: Double {
        didSet {
            UserDefaults.standard.set(restDurationSecs, forKey: "restDurationSecs")
        }
    }

    var isRunning = false
    var isPaused = false
    var isResting = false
    var timeRemaining: TimeInterval = 0
    var hasPostponeBeenUsedThisCycle = false
    
    var canPostpone: Bool {
        isResting && !hasPostponeBeenUsedThisCycle && !isInPostponedWork
    }

    private var isInPostponedWork = false
    private var savedRestRemaining: TimeInterval?
    private var timerTask: Task<Void, Never>?
    private var sleepObserverTasks = [Task<Void, Never>]()
    private let overlayManager: any OverlayManaging
    private var restStartedAt: Date?
    private var isSystemAsleep = false
    private var wasAutoPausedBySystem = false

    init(overlayManager: any OverlayManaging) {
        self.overlayManager = overlayManager
        self.workDurationSecs = UserDefaults.standard.double(forKey: "workDurationSecs")
        self.restDurationSecs = UserDefaults.standard.double(forKey: "restDurationSecs")
        
        // Set defaults if not previously saved
        if self.workDurationSecs == 0 { self.workDurationSecs = 1500 }
        if self.restDurationSecs == 0 { self.restDurationSecs = 300 }
        
        setupSleepObservers()
    }
    
    init() {
        self.overlayManager = OverlayManager()
        self.workDurationSecs = UserDefaults.standard.double(forKey: "workDurationSecs")
        self.restDurationSecs = UserDefaults.standard.double(forKey: "restDurationSecs")
        
        if self.workDurationSecs == 0 { self.workDurationSecs = 1500 }
        if self.restDurationSecs == 0 { self.restDurationSecs = 300 }
        
        setupSleepObservers()
    }

    func start() {
        timeRemaining = workDurationSecs
        isRunning = true
        isPaused = false
        wasAutoPausedBySystem = false
        runTimer()
    }

    func pause() {
        if isResting {
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
        isInPostponedWork = false
        wasAutoPausedBySystem = false
        timeRemaining = 0
        restStartedAt = nil
        savedRestRemaining = nil
        hasPostponeBeenUsedThisCycle = false
        overlayManager.dismissOverlays()
    }

    func postpone() {
        guard isResting && !hasPostponeBeenUsedThisCycle && !isInPostponedWork else { return }

        savedRestRemaining = timeRemaining
        isInPostponedWork = true
        hasPostponeBeenUsedThisCycle = true
        isResting = false
        timeRemaining = 60
        overlayManager.dismissOverlays()
    }

    private func runTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }

    private func tick() {
        if isInPostponedWork {
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                resumeRest()
            }
        } else if isResting, let anchor = restStartedAt {
            timeRemaining = max(0, restDurationSecs - Date().timeIntervalSince(anchor))

            if timeRemaining <= 0 && !isSystemAsleep {
                timerTask?.cancel()
                restStartedAt = nil
                isResting = false
                overlayManager.dismissOverlays()
                start()
            }
        } else {
            timeRemaining -= 1

            if timeRemaining <= 0 {
                timerTask?.cancel()
                triggerRestPhase()
            }
        }
    }

    private func resumeRest() {
        guard let saved = savedRestRemaining else { return }

        isInPostponedWork = false
        isResting = true
        timeRemaining = saved

        let elapsed = restDurationSecs - saved
        restStartedAt = Date().addingTimeInterval(-elapsed)

        savedRestRemaining = nil
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    private func triggerRestPhase() {
        isResting = true
        isInPostponedWork = false
        hasPostponeBeenUsedThisCycle = false
        savedRestRemaining = nil
        restStartedAt = Date()
        timeRemaining = restDurationSecs
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    private func setupSleepObservers() {
        let notifications: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]
        
        for name in notifications {
            sleepObserverTasks.append(Task { [weak self] in
                let center = NotificationCenter.default
                for await _ in center.notifications(named: name) {
                    self?.handleNotification(name)
                }
            })
        }
    }

    private func handleNotification(_ name: NSNotification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, 
             NSWorkspace.screensDidSleepNotification:
            handleSleep()
        case NSWorkspace.didWakeNotification,
             NSWorkspace.screensDidWakeNotification:
            handleWake()
        default: break
        }
    }

    private func handleSleep() {
        isSystemAsleep = true
        guard isRunning && !isPaused && !isResting else { return }
        pause()
        wasAutoPausedBySystem = true
    }

    private func handleWake() {
        isSystemAsleep = false

        if isResting, let anchor = restStartedAt {
            let elapsed = Date().timeIntervalSince(anchor)
            if elapsed >= restDurationSecs {
                timerTask?.cancel()
                restStartedAt = nil
                isResting = false
                isRunning = false
                overlayManager.dismissOverlays()
            }
        } else if wasAutoPausedBySystem {
            wasAutoPausedBySystem = false
            resume()
        }
    }
}
