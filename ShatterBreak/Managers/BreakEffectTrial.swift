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

        let sample = TimerState(
            overlays: overlays,
            defaults: timer.defaults,
            statistics: StatisticsStore(defaults: InMemoryKeyValueStore()),
            showing: .starting(.rest, duration: restDuration)
        )
        self.sample = sample
        overlays.show(sample, .animated)

        // Swallowed rather than passed on: the first thing the user does means "enough",
        // including a click that would otherwise land on the sample's own Postpone button.
        interruption = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
            return nil
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
