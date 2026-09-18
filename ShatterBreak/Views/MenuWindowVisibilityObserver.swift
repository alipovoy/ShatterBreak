import AppKit
import SwiftUI

struct MenuWindowVisibilityObserver: NSViewRepresentable {
    @Binding var isVisible: Bool

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: $isVisible)
    }

    @MainActor
    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { window in
            context.coordinator.observe(window: window)
        }
        return view
    }

    /// Hands over the fresh binding and nothing else. Reading the window here and writing
    /// the answer back would land inside SwiftUI's update; the window's own notifications
    /// carry every transition on their own.
    @MainActor
    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.isVisible = $isVisible
    }

    @MainActor
    final class Coordinator: NSObject {
        var isVisible: Binding<Bool>
        private weak var window: NSWindow?

        init(isVisible: Binding<Bool>) {
            self.isVisible = isVisible
        }

        func observe(window: NSWindow?) {
            guard self.window !== window else {
                updateVisibility()
                return
            }

            removeObservers()
            self.window = window

            guard let window else {
                isVisible.wrappedValue = false
                return
            }

            let center = NotificationCenter.default
            let names: [NSNotification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification
            ]

            names.forEach { name in
                center.addObserver(
                    self,
                    selector: #selector(handleWindowNotification(_:)),
                    name: name,
                    object: window
                )
            }

            updateVisibility()
        }

        @objc private func handleWindowNotification(_ notification: Notification) {
            updateVisibility()
        }

        private func updateVisibility() {
            guard let window else {
                if isVisible.wrappedValue {
                    isVisible.wrappedValue = false
                }
                return
            }

            let nextValue = window.isVisible && window.occlusionState.contains(.visible)
            if isVisible.wrappedValue != nextValue {
                isVisible.wrappedValue = nextValue
            }
        }
        private func removeObservers() {
            // swiftlint:disable:next notification_center_detachment
            NotificationCenter.default.removeObserver(self)
        }
    }
}
