import AppKit

/// Puts a real break on screen for a few seconds, so an effect can be judged before a break
/// arrives.
///
/// The effect rather than an illustration of it, because none of what distinguishes these
/// effects survives a thumbnail: a five-point blur across a whole screen, or a fog the
/// window server draws behind the overlay, is invisible at the size of a picker card.
///
/// The sample is disposable: a throwaway statistics store, so nothing is tallied, and a plan
/// nothing schedules, so it never transitions.
///
/// It presents through the *app's* presenter, so the break window keeps one owner. That is
/// what makes both directions decidable — a sample is refused while a break is up
/// (``canStart``), and a break falling due mid-sample takes the window, after which the
/// trial ends without dismissing what is no longer its own.
@MainActor
@Observable
final class BreakEffectTrial {
    /// Long enough to watch the entrance settle, short enough not to feel shut out.
    static let defaultDuration: Duration = .seconds(5)

    private(set) var isRunning = false

    /// How long the sample stays up. Shortened by tests.
    let duration: Duration

    /// The app's timer: the sample borrows its overlay layer, preferences and break length
    /// rather than assembling a parallel set.
    @ObservationIgnored
    private let timer: TimerState

    @ObservationIgnored
    private let sampleClock: (any TimerClock)?

    private var sample: TimerState?
    private var timeout: Task<Void, Never>?
    private var interruption: Any?

    /// - Parameter sampleClock: the clock the sample reads its countdown from. Injected by
    ///   tests; the app takes the system one.
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

    /// There is one break window, so a sample during a real break would replace it rather
    /// than sit alongside it.
    var canStart: Bool {
        isRunning == false && timer.isResting == false && timer.awaitingReturn == false
    }

    func start() {
        guard canStart else { return }
        isRunning = true

        // Whatever consent is settled by the time the window goes up is what a break
        // arriving this second would get, which is the honest thing to show.
        overlays.prepare()

        // A notification centre of its own, which nothing posts to. The sample exists to be
        // looked at: wired to the workspace's, a display sleep inside these few seconds
        // would drive the sample's own reducer, arm real timers for it, and let it emit
        // effects — including a dismissal — through the presenter the app shares with it.
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

        // Weakly, here and in the monitor: a Preferences window closed mid-sample should
        // take the sample with it, and a strong capture would defer that to the timeout.
        let duration = duration
        timeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard Task.isCancelled == false else { return }
            self?.end()
        }
    }

    /// Ends the sample on the user's first key or click, reporting whether that event was
    /// the sample's to take.
    ///
    /// Swallowed while the sample is up, since the first thing the user does means "enough"
    /// — including a click that would otherwise land on the sample's own Postpone button.
    /// Once a real break has taken the window the event belongs to it, and passing it on is
    /// the difference between dismissing a sample and eating the user's "I'm back".
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

        // Only if the sample is still what is on screen: a break that took the window
        // mid-sample would otherwise be dismissed here.
        if overlays.presenting() === sample {
            overlays.dismiss()
        }
        sample = nil
    }

    private var overlays: OverlayPresenter { timer.overlays }

    /// The user's own break length, so the sample's clock reads like the real thing.
    private var restDuration: TimeInterval { timer.restDurationSecs }
}
