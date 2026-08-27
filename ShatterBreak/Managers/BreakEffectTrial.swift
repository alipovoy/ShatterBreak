import AppKit

/// Puts a real break on screen for a few seconds, so an effect can be judged before a
/// break arrives.
///
/// Not an illustration of the effect — the effect. It goes through ``OverlayPresenter``
/// like any break: over the live desktop, at the window level the preference selects, with
/// the entrance and sound the break plays. None of that survives a thumbnail. The frost is
/// a five-point blur across a whole screen, the fog is the window server blurring whatever
/// sits behind the overlay window, and at the size of a picker card both are invisible.
///
/// The sample is disposable in every way that could touch the app: its own throwaway
/// statistics store, so nothing is tallied, and a plan nothing schedules, so it never
/// transitions to anything.
@MainActor
@Observable
final class BreakEffectTrial {
    /// Long enough to watch the entrance settle, short enough that nobody feels shut out
    /// of their machine — and any key or click ends it sooner.
    static let defaultDuration: Duration = .seconds(5)

    private(set) var isRunning = false

    /// How long this trial's sample stays up. Shortened by tests, which would otherwise
    /// wait out the real thing to prove it ends on its own.
    let duration: Duration

    private let injectedOverlays: OverlayPresenter?
    private let defaults: any KeyValueStore

    /// Built on first use. A live presenter creates an `OverlayManager`, which starts
    /// observing display changes, and a view that is initialised more often than it is
    /// shown should not be creating those to throw away.
    @ObservationIgnored
    private lazy var overlays: OverlayPresenter = injectedOverlays ?? .live(defaults: defaults)

    /// Held while the sample is up: the overlay reads its clock from this.
    private var sample: TimerState?
    private var timeout: Task<Void, Never>?
    private var interruption: Any?

    init(
        overlays: OverlayPresenter? = nil,
        defaults: any KeyValueStore = UserDefaults.standard,
        duration: Duration = BreakEffectTrial.defaultDuration
    ) {
        self.defaults = defaults
        self.injectedOverlays = overlays
        self.duration = duration
    }

    isolated deinit {
        // Only if a sample is actually up: touching `overlays` otherwise would build the
        // presenter this trial spent its whole life avoiding.
        guard isRunning else { return }
        end()
    }

    func start() {
        guard isRunning == false else { return }
        isRunning = true

        // The consent a real break needs, asked for by an action that plainly means "I
        // want to see Shatter". Whatever is settled by the time the window goes up is what
        // a break arriving this second would get, which is the honest thing to show.
        overlays.prepare()

        let sample = TimerState(
            overlays: overlays,
            defaults: defaults,
            statistics: StatisticsStore(defaults: InMemoryKeyValueStore()),
            showing: .starting(.rest, duration: restDuration)
        )
        self.sample = sample
        overlays.show(sample, .animated)

        // Swallowed rather than passed on: while the sample is up, the first thing the
        // user does means "enough", including a click that would otherwise land on the
        // sample's own Postpone button and act on a break that does not exist.
        interruption = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
            return nil
        }

        // Weakly, both here and in the monitor: neither is a reason to keep a trial alive.
        // A Preferences window closed mid-sample should take the sample with it, which is
        // `deinit`'s job, and a strong capture here would defer that until the sample ran
        // out on its own.
        let duration = duration
        timeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard Task.isCancelled == false else { return }
            self?.end()
        }
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

        overlays.dismiss()
        sample = nil
    }

    /// The user's own break length, so the sample's clock reads like the real thing rather
    /// than announcing a number no break of theirs would show.
    private var restDuration: TimeInterval {
        defaults.duration(forKey: PreferenceKeys.restDurationSecs,
                          default: PreferenceDefaults.restDurationSecs)
    }
}
