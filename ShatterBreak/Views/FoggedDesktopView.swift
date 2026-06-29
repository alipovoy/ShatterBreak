import AppKit
import SwiftUI

/// Renders the live desktop behind the overlay window as fogged glass using a
/// behind-window `NSVisualEffectView`.
///
/// Unlike ``FrostedCaptureView``, this needs no screen capture — and therefore no
/// Screen Recording permission: the window server blurs whatever is composited
/// beneath the transparent overlay window in real time.
///
/// Behind-window vibrancy blurs heavily — like steam fogging a window rather than
/// the shatter effect's lightly etched frosted glass — and that radius isn't
/// adjustable. Making the blur layer partially transparent lets the sharp desktop
/// read through, softening the fog so it doesn't read as an opaque wall (issue #62).
/// A slight dim sits on top.
///
/// Used both for the standalone fogged effect and as the shatter effect's fallback
/// when a screenshot is unavailable, so the cracked-glass treatment always has a
/// blurred backing instead of flat black.
struct FoggedDesktopView: View {
    /// The vibrancy blending mode. Production blurs the live desktop behind the
    /// overlay window (`.behindWindow`); previews pass `.withinWindow` so the blur
    /// can sample a stand-in wallpaper composited behind it, since behind-window
    /// vibrancy cannot sample sibling views.
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    private enum Fog {
        static let material: NSVisualEffectView.Material = .fullScreenUI
        /// How opaque the heavy behind-window blur is. Below 1 the sharp desktop
        /// reads through, lightening the fog so the desktop stays faintly visible.
        static let blurOpacity: CGFloat = 0.65
        static let dimOpacity: CGFloat = 0.1
    }

    var body: some View {
        DesktopBlurView(material: Fog.material, blendingMode: blendingMode, alpha: Fog.blurOpacity)
            .overlay(Color.black.opacity(Fog.dimOpacity))
    }
}

/// Bridges a behind-window `NSVisualEffectView` into SwiftUI. Kept private to
/// ``FoggedDesktopView`` since the dim and any future styling belong with it.
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

#Preview("Fogged Desktop") {
    // Behind-window vibrancy can't sample a sibling view, so the preview uses
    // within-window blending to fog a stand-in wallpaper, mirroring the shatter
    // preview's glass-over-wallpaper look.
    ZStack {
        PreviewWallpaper()
        FoggedDesktopView(blendingMode: .withinWindow)
    }
    .frame(width: 480, height: 300)
}
