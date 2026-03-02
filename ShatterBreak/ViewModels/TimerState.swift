import SwiftUI
import AppKit
import Combine

@MainActor
class TimerState: ObservableObject {
    @AppStorage("workDurationSecs") var workDurationSecs: Double = 1500
    @AppStorage("restDurationSecs") var restDurationSecs: Double = 300

    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isResting = false
    @Published var timeRemaining: TimeInterval = 0

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let overlayManager = OverlayManager()

    // Tracks if the system forced a pause, so we can auto-resume on wake
    private var wasAutoPausedBySystem = false

    init() {
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
        isPaused = true
        timer?.cancel()
    }

    func resume() {
        isPaused = false
        runTimer()
    }

    func stop() {
        timer?.cancel()
        isRunning = false
        isPaused = false
        wasAutoPausedBySystem = false
        timeRemaining = 0
        isResting = false
        overlayManager.dismissOverlays()
    }

    private func runTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            self.timeRemaining -= 1

            if self.timeRemaining <= 0 {
                self.timer?.cancel()
                if self.isResting {
                    self.overlayManager.dismissOverlays()
                    self.isResting = false
                    self.start()
                } else {
                    self.triggerNotifyAction()
                }
            }
        }
    }

    private func triggerNotifyAction() {
        isResting = true
        timeRemaining = restDurationSecs
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    // MARK: - Sleep & Display Observation
    private func setupSleepObservers() {
        let workspaceNC = NSWorkspace.shared.notificationCenter

        // 1. System Sleep
        workspaceNC.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.handleSleep() }
            .store(in: &cancellables)

        // 2. Display Sleep
        workspaceNC.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.handleSleep() }
            .store(in: &cancellables)

        // 3. System Wake
        workspaceNC.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)

        // 4. Display Wake
        workspaceNC.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)
    }

    private func handleSleep() {
        // If the timer is actively running, pause it and remember that WE paused it
        if isRunning && !isPaused {
            pause()
            wasAutoPausedBySystem = true
        }
    }

    private func handleWake() {
        // If the system wakes up and we were the ones who paused it, resume automatically
        if wasAutoPausedBySystem {
            resume()
            wasAutoPausedBySystem = false
        }
    }
}
