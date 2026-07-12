import Foundation

/// Controls whether the work timer should start automatically when a break ends
/// or wait for the user to manually indicate they have returned.
///
/// The lowercase `rawValue` of each case is the string persisted in user defaults;
/// an unrecognized stored value decodes to `nil`, letting the read site fall back
/// to a default rather than trusting a corrupt preference.
enum WorkStartMode: String {
    case automatic
    case manual
}
