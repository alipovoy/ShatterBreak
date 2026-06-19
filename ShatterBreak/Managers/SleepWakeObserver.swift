import AppKit

/// Observes workspace sleep/wake notifications and forwards them to its owner.
///
/// Mirrors `AppActiveObserver`: a dedicated `NSObject` subscriber with an injected
/// `NotificationCenter`, weak-captured callbacks to avoid a retain cycle with its
/// owner, and `deinit` cleanup.
///
/// Registration is synchronous (selector-based), so observers are guaranteed to be
/// subscribed by the time `startObserving` returns. This matters because sleep/wake
/// notifications can be posted immediately after a timer starts, and
/// `NotificationCenter` does not buffer for a not-yet-subscribed consumer.
/// `NSWorkspace` sleep/wake notifications are delivered on the main thread, so the
/// `@objc` handlers run on the main actor.
@MainActor
final class SleepWakeObserver: NSObject {
    private let notificationCenter: NotificationCenter
    private var onSleep: (@MainActor () -> Void)?
    private var onWake: (@MainActor () -> Void)?
    private var isObserving = false

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
    }

    /// Subscribes to system and display sleep/wake notifications. Idempotent: a second
    /// call while already observing keeps the original callbacks.
    func startObserving(
        onSleep: @escaping @MainActor () -> Void,
        onWake: @escaping @MainActor () -> Void
    ) {
        guard isObserving == false else { return }

        self.onSleep = onSleep
        self.onWake = onWake

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            notificationCenter.addObserver(self, selector: #selector(handleSleep), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            notificationCenter.addObserver(self, selector: #selector(handleWake), name: name, object: nil)
        }

        isObserving = true
    }

    func stopObserving() {
        guard isObserving else { return }

        notificationCenter.removeObserver(self)
        onSleep = nil
        onWake = nil
        isObserving = false
    }

    @objc private func handleSleep() {
        onSleep?()
    }

    @objc private func handleWake() {
        onWake?()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
