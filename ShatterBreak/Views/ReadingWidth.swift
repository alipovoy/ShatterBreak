import SwiftUI

extension View {
    /// Caps a block of prose at a comfortable reading width without letting it decide how
    /// wide the enclosing `Form` is.
    ///
    /// A `Form` sizes itself from its content's ideal widths, so a long warning stated as
    /// `maxWidth` alone would stretch the Settings window to fit one sentence. An ideal
    /// width answers that question modestly and `maxWidth` then lets the text fill and wrap
    /// to whatever the surrounding controls settle on.
    ///
    /// Shared by every warning and standing note in Preferences so they all wrap alike.
    func readingWidth() -> some View {
        frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}
