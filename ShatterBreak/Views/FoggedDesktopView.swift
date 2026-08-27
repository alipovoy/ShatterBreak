import AppKit
import SwiftUI

/// The live desktop behind the overlay window, fogged by a behind-window
/// `NSVisualEffectView` — so unlike ``FrostedCaptureView`` it needs no capture permission.
///
/// The blur radius isn't adjustable and is heavy, so the layer is made partially
/// transparent to let the sharp desktop read through rather than reading as an opaque wall
/// (#62).
///
/// Also the shatter effect's fallback when a screenshot is unavailable, so the cracked glass
/// always has a blurred backing instead of flat black.
struct FoggedDesktopView: View {
    /// Previews pass `.withinWindow` so the blur can sample a stand-in wallpaper behind it;
    /// behind-window vibrancy cannot sample sibling views.
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    private enum Fog {
        static let material: NSVisualEffectView.Material = .fullScreenUI
        /// Below 1 the sharp desktop reads through, so it stays faintly visible.
        static let blurOpacity: CGFloat = 0.65
        static let dimOpacity: CGFloat = 0.1
    }

    var body: some View {
        DesktopBlurView(material: Fog.material, blendingMode: blendingMode, alpha: Fog.blurOpacity)
            .overlay(Color.black.opacity(Fog.dimOpacity))
    }
}

/// Bridges a behind-window `NSVisualEffectView` into SwiftUI.
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
