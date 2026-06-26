import CoreGraphics

/// The set of changes needed to bring a live group of overlay windows back in line
/// with the displays currently attached, computed purely so it can be exercised
/// without a window server (mirroring `OverlayManager.applyCapturedImages`).
///
/// `OverlayManager` enumerates displays once when a break begins; this diff is how it
/// reacts to later reconfiguration (issue #3): a main display unplugged, a clamshell
/// lid opened mid-break, or a display changing resolution. Each window stays pinned to
/// its own display — overlays are never moved — so a disappearing display's window is
/// torn down rather than left to drift onto, and overflow, a surviving display.
struct OverlayReconciliation: Equatable {
    /// Displays whose overlay window should be torn down (the display is gone).
    var removed: [CGDirectDisplayID]

    /// Displays that gained an overlay and need a window built for them.
    var added: [ScreenInfo]

    /// Displays that kept their overlay but whose frame changed (resolution or
    /// arrangement), so the existing window must be resized to stay reachable.
    var reframed: [ScreenInfo]

    var isEmpty: Bool {
        removed.isEmpty && added.isEmpty && reframed.isEmpty
    }

    /// Diffs the current overlay windows (keyed by display, with their frames) against
    /// the displays now available. Iterates `availableScreens` to keep `added`/`reframed`
    /// in a stable, caller-defined order.
    static func plan(
        currentWindows: [CGDirectDisplayID: CGRect],
        availableScreens: [ScreenInfo]
    ) -> OverlayReconciliation {
        let availableIDs = Set(availableScreens.map(\.displayID))

        let removed = currentWindows.keys
            .filter { availableIDs.contains($0) == false }
            .sorted()

        var added: [ScreenInfo] = []
        var reframed: [ScreenInfo] = []

        for screen in availableScreens {
            if let existingFrame = currentWindows[screen.displayID] {
                if existingFrame != screen.frame {
                    reframed.append(screen)
                }
            } else {
                added.append(screen)
            }
        }

        return OverlayReconciliation(removed: removed, added: added, reframed: reframed)
    }
}
