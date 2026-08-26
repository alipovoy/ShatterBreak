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
///
/// It presents through the *app's* presenter rather than one of its own, so the break
/// window keeps a single owner. That is what makes the two directions decidable: a sample
/// is refused while a real break is up (``canStart``), and a real break falling due
/// mid-sample simply takes the window, after which the trial ends without dismissing
/// something that is no longer its own.
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

    /// The app's timer, for its overlay layer, its preferences and its break length. The
    /// sample borrows all three rather than assembling a parallel set of its own.
    @ObservationIgnored
    private let timer: TimerState

    /// Held while the sample is up: the overlay reads its clock from this.
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

    /// Whether a sample can be shown right now.
    ///
    /// A real break already owns the screen during rest and while waiting for the user to
    /// come back, and there is exactly one break window: a sample then would not sit
    /// alongside the break, it would replace it.
    var canStart: Bool {
        isRunning == false && timer.isResting == false && timer.awaitingReturn == false
    }

    func start() {
        guard canStart else { return }
        isRunning = true

        // The consent a real break needs, asked for by an action that plainly means "I
        // want to see Shatter". Whatever is settled by the time the window goes up is what
        // a break arriving this second would get, which is the honest thing to show.
        overlays.prepare()

        let sample = TimerState(
            overlays: overlays,
            defaults: timer.defaults,
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

        // Only if the sample is still what is on screen. A break falling due mid-sample
        // presents through this same presenter and takes the window; dismissing here on
        // the strength of having shown something a few seconds ago would close the user's
        // actual break.
        if overlays.presenting() === sample {
            overlays.dismiss()
        }
        sample = nil
    }

    private var overlays: OverlayPresenter { timer.overlays }

    /// The user's own break length, so the sample's clock reads like the real thing rather
    /// than announcing a number no break of theirs would show.
    private var restDuration: TimeInterval { timer.restDurationSecs }
}
