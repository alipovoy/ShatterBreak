/// How a break overlay should announce its arrival.
///
/// Threaded through ``OverlayPresenter/show`` instead of a bare `Bool`: `show` is a
/// closure-typed property, and Swift does not surface argument labels for closure
/// values at their call sites, so a raw `Bool` reads as an undocumented literal
/// (`overlays.show(self, true)`). The case name carries that meaning instead.
enum OverlayPresentationStyle: Equatable {
    /// A break beginning now: plays the full shake/entrance intro and sound.
    case animated
    /// The break already elapsed silently — an absence served as the break (issue
    /// #76) — so the window is presented already settled, with no intro or sound.
    case settled
}
