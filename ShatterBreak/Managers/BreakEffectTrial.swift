import AppKit

/// Puts a real break on screen for a few seconds, the effect rather than an illustration of
/// it: nothing that distinguishes a display-wide blur from a fog drawn behind the overlay
/// survives a picker card.
///
/// Disposable — a throwaway statistics store tallies nothing, and nothing schedules the plan
/// — but presented through the *app's* presenter, so the break window keeps one owner.
@MainActor
@Observable
final class BreakEffectTrial {
    /// Long enough to watch the entrance settle, short enough not to feel shut out.
    static let defaultDuration: Duration = .seconds(5)

    private(set) var isRunning = false

    /// How long the sample stays up. Shortened by tests.
    let duration: Duration

    /// The sample borrows this one's overlay layer, preferences and break length rather than
    /// assembling a parallel set.
    @ObservationIgnored
    private let timer: TimerState

    @ObservationIgnored
    private let sampleClock: (any TimerClock)?

    private var sample: TimerState?
    private var timeout: Task<Void, Never>?
    private var interruption: Any?

    /// - Parameter sampleClock: injected by tests; the app takes the system clock.
    init(
        timer: TimerState,
        duration: Duration = BreakEffectTrial.defaultDuration,
        sampleClock: (any TimerClock)? = nil
    ) {
        self.timer = timer
        self.duration = duration
        self.sampleClock = sampleClock
    }

    isolated deinit {
        guard isRunning else { return }
        end()
    }

    var canStart: Bool { isRunning == false && breakWindowIsFree }

    func start() async {
        guard canStart else { return }
        isRunning = true

        // Awaited, unlike the timer's own preparation: the sample is presented in the next
        // breath, and an unsettled capture consent renders the fallback effect instead of
        // the one being sampled.
        await overlays.prepare()

        // A real break may have claimed the window meanwhile, and presenting would take it.
        guard isRunning, breakWindowIsFree else { return end() }

        // A notification centre of its own, which nothing posts to. Wired to the workspace's,
        // a display sleep inside these few seconds would drive the sample's reducer and let it
        // emit effects — a dismissal among them — through the shared presenter.
        let sample = TimerState(
            overlays: overlays,
            defaults: timer.defaults,
            clock: sampleClock,
            workspaceNotificationCenter: NotificationCenter(),
            statistics: StatisticsStore(defaults: InMemoryKeyValueStore()),
            showing: .starting(.rest, duration: restDuration)
        )
        self.sample = sample
        overlays.show(sample, .animated)

        interruption = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { interrupt() } ? nil : event
        }

        // Weakly, here and in the monitor: a Preferences window closed mid-sample should take
        // the sample with it, and a strong capture would defer that to the timeout.
        let duration = duration
        timeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard Task.isCancelled == false else { return }
            self?.end()
        }
    }

    /// Ends the sample on the user's first key or click, reporting whether that event was the
    /// sample's to take. Swallowed while the sample is up; once a real break holds the window
    /// the event is the break's, and eating it would eat the user's "I'm back".
    func interrupt() -> Bool {
        let wasOurs = overlays.presenting() === sample
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
        if overlays.presenting() === sample {
            overlays.dismiss()
        }
        sample = nil
    }

    /// There is one break window, so a sample during a real break would replace it.
    private var breakWindowIsFree: Bool {
        timer.isResting == false && timer.awaitingReturn == false
    }

    private var overlays: OverlayPresenter { timer.overlays }

    private var restDuration: TimeInterval { timer.restDurationSecs }
}
