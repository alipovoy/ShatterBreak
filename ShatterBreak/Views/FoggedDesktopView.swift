import AppKit
import SwiftUI

/// The live desktop behind the overlay, fogged by a behind-window `NSVisualEffectView`, so
/// it needs no capture. Also Shatter's fallback when a screenshot is unavailable.
struct FoggedDesktopView: View {
    /// `.withinWindow` in previews: behind-window vibrancy cannot sample sibling views.
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    private enum Fog {
        static let material: NSVisualEffectView.Material = .fullScreenUI
        /// The blur radius is fixed and heavy; below 1 the desktop reads through.
        static let blurOpacity: CGFloat = 0.65
        static let dimOpacity: CGFloat = 0.1
    }

    var body: some View {
        DesktopBlurView(material: Fog.material, blendingMode: blendingMode, alpha: Fog.blurOpacity)
            .overlay(Color.black.opacity(Fog.dimOpacity))
    }
}

private struct DesktopBlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let alpha: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.material = material
        view.state = .active
        view.alphaValue = alpha
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.alphaValue = alpha
    }
}
