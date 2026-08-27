import SwiftUI

extension View {
    /// Caps prose at a readable width without letting it size the enclosing `Form`.
    ///
    /// A `Form` sizes itself from its content's ideal widths, so `maxWidth` alone would
    /// stretch the window to fit one sentence. The ideal width answers modestly; `maxWidth`
    /// then lets the text wrap to whatever the surrounding controls settle on.
    func readingWidth() -> some View {
        frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}
