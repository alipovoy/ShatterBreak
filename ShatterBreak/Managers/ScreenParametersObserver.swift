import AppKit

/// Observes display-reconfiguration notifications and forwards them to its owner.
///
/// Mirrors `SleepWakeObserver`/`AppActiveObserver`: a dedicated `NSObject` subscriber
/// with an injected `NotificationCenter`, a weak-captured callback to avoid a retain
/// cycle with its owner, and `deinit` cleanup.
///
/// `NSApplication.didChangeScreenParametersNotification` fires whenever displays are
/// connected, disconnected, rearranged, or change resolution — including a main
/// display being unplugged or a clamshell lid opening mid-break. It is posted on the
/// default center on the main thread, so the `@objc` handler runs on the main actor.
@MainActor
final class ScreenParametersObserver: NSObject {
    private let notificationCenter: NotificationCenter
    private var onChange: (@MainActor () -> Void)?
    private var isObserving = false

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    /// Subscribes to screen-parameter changes. Idempotent: a second call while already
    /// observing keeps the original callback.
    func startObserving(onChange: @escaping @MainActor () -> Void) {
        guard isObserving == false else { return }

        self.onChange = onChange
        notificationCenter.addObserver(
            self,
            selector: #selector(handleChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        isObserving = true
    }

    func stopObserving() {
        guard isObserving else { return }

        notificationCenter.removeObserver(self)
        onChange = nil
        isObserving = false
    }

    @objc private func handleChange() {
        onChange?()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
