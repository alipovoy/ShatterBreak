import SwiftUI

extension View {
    /// A `Form` sizes itself from ideal widths, so `maxWidth` alone would stretch the window
    /// to fit one sentence.
    func readingWidth() -> some View {
        frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
    }
}
