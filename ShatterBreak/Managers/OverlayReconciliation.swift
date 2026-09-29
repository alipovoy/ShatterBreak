import CoreGraphics

/// What it takes to bring the break's windows back in line with the displays attached
/// (issue #3): a display unplugged, a lid opened, a resolution changed.
struct OverlayReconciliation: Equatable {
    var removed: [CGDirectDisplayID]
    var added: [ScreenInfo]
    var reframed: [ScreenInfo]

    var isEmpty: Bool {
        removed.isEmpty && added.isEmpty && reframed.isEmpty
    }

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
