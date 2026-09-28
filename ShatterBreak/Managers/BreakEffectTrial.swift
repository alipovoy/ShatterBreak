import AppKit

/// Puts a real break on screen for a few seconds: nothing that tells a display-wide blur
/// from a fog drawn behind the overlay survives a picker card.
///
/// Presented through the timer's own presenter, so the break window keeps one owner.
@MainActor
@Observable
final class BreakEffectTrial {
    static let defaultDuration: Duration = .seconds(5)

    private(set) var isRunning = false

    let duration: Duration

    @ObservationIgnored
    private let timer: TimerState

    private var sample: TimerState?
    private var timeout: Task<Void, Never>?
    private var interruption: Any?

    init(timer: TimerState, duration: Duration = BreakEffectTrial.defaultDuration) {
        self.timer = timer
        self.duration = duration
    }

    isolated deinit {
        guard isRunning else { return }
        end()
    }

    var canStart: Bool { isRunning == false && breakWindowIsFree && timer.overlays != nil }

    func start() async {
        guard canStart, let overlays = timer.overlays else { return }
        isRunning = true

        // Awaited, unlike the timer's: the sample is presented in the next breath, and an
        // unsettled consent would render the fallback effect instead of the one sampled.
        await overlays.prepareCapture()

        // A real break may have claimed the window meanwhile. With every display asleep,
        // `show` would draw nothing yet still hold the window, swallowing the next click.
        guard isRunning, breakWindowIsFree, overlays.hasAwakeScreen else { return end() }

        let sample = TimerState.parked(.starting(.rest, duration: timer.restDurationSecs), defaults: timer.defaults)
        self.sample = sample
        overlays.show(sample, style: .animated)

        interruption = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { interrupt() } ? nil : event
        }

        // Weakly: a Preferences window closed mid-sample takes the sample with it.
        let duration = duration
        timeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard Task.isCancelled == false else { return }
            self?.end()
        }
    }

    /// Ends the sample on the user's first key or click, reporting whether the event was the
    /// sample's to swallow. Once a real break holds the window it is that break's "I'm back".
    func interrupt() -> Bool {
        let wasOurs = timer.overlays?.presentedState === sample
        end()
        return wasOurs
    }

    func end() {
        guard isRunning else { return }
        isRunning = false

        timeout?.cancel()
        timeout = nil
        if let interruption {
            NSEvent.removeMonitor(interruption)
        }
        interruption = nil

        // A break that took the window mid-sample must not be dismissed here.
        if let overlays = timer.overlays, overlays.presentedState === sample {
            overlays.dismiss()
        }
        sample = nil
    }

    private var breakWindowIsFree: Bool {
        timer.isResting == false && timer.awaitingReturn == false
    }
}
