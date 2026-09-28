import Foundation

/// macOS 15's second capture consent, the monthly "bypass the private window picker"
/// dialog (issue #90). Nothing can preflight it; only attempting a capture tells.
enum DirectCaptureAccess: Equatable, Sendable {
    /// Not yet asked, or the answer is in flight. Treated as not allowed: capturing now is
    /// what puts the dialog over a break.
    case unknown
    case allowed
    case refused
}
