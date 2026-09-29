/// How a break overlay announces its arrival.
enum OverlayPresentationStyle: Equatable {
    /// A break beginning now: the entrance and its sound.
    case animated
    /// A break already under way or already over, as after an absence (issue #76): no
    /// entrance, no sound.
    case settled
}
