import AppKit
import SwiftUI

/// Makes the window follow the active Space rather than remembering its last Space.
private struct ActiveSpaceWindowModifier: NSViewRepresentable {
    @MainActor
    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { window in
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }
        return view
    }

    @MainActor
    func updateNSView(_ nsView: WindowTrackingView, context: Context) {}
}

extension View {
    func moveToActiveSpace() -> some View {
        background(ActiveSpaceWindowModifier())
    }
}
