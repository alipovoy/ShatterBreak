import SwiftUI

/// A stand-in desktop for previews, since a real screen capture isn't available in Xcode
/// Previews.
///
/// Deliberately busy. Every effect the app puts over the screen — the frost, the fog, the
/// cracked glass — works by destroying detail, so a stand-in with no detail cannot show
/// what any of them do: a blurred gradient is the same gradient. Menu bar, window chrome,
/// text rules, icons and a dock give the blur edges to eat and the glass something to
/// distort, which is the whole reason to look at those previews.
///
/// Shared by every effect preview so the treatments are compared over the same desktop.
struct PreviewWallpaper: View {
    static let size = CGSize(width: 480, height: 300)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [.blue, .indigo, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            DesktopIcons()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 32)
                .padding(.trailing, 16)

            WindowMockup()
                .frame(width: 280, height: 180)
                .offset(x: -60, y: 56)

            MenuBarStrip()

            DockStrip()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }
}

/// The menu bar: the sharpest horizontal edge on any desktop, and the first thing a blur
/// softens.
private struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.system(size: 10))
            TextRule(width: 34, height: 5)
            TextRule(width: 26, height: 5)
            TextRule(width: 30, height: 5)
            TextRule(width: 22, height: 5)

            Spacer()

            Image(systemName: "wifi")
            Image(systemName: "battery.75")
            Text(verbatim: "9:41")
                .font(.system(size: 9, weight: .medium))
        }
        .font(.system(size: 9))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.black.opacity(0.25))
    }
}

/// A document window: title bar, sidebar, and ruled text. The text rules matter most —
/// evenly spaced thin lines are what a blur turns to mush first.
private struct WindowMockup: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach([Color.red, .yellow, .green], id: \.self) { light in
                    Circle().fill(light).frame(width: 7, height: 7)
                }
                TextRule(width: 60, height: 5, opacity: 0.35)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(.regularMaterial)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<6, id: \.self) { row in
                        TextRule(width: row.isMultiple(of: 3) ? 44 : 34, height: 5, opacity: 0.3)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(width: 78, alignment: .leading)
                .background(.thinMaterial)

                VStack(alignment: .leading, spacing: 6) {
                    TextRule(width: 92, height: 7, opacity: 0.45)
                    ForEach(WindowMockup.lineWidths, id: \.self) { width in
                        TextRule(width: width, height: 4, opacity: 0.25)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    /// Ragged like real prose, so the blur has uneven edges to soften rather than a block.
    private static let lineWidths: [CGFloat] = [150, 138, 156, 96, 148, 132, 60, 144, 120]
}

private struct DesktopIcons: View {
    var body: some View {
        VStack(spacing: 14) {
            icon("folder.fill")
            icon("doc.text.fill")
            icon("externaldrive.fill")
        }
        .foregroundStyle(.white)
    }

    private func icon(_ systemName: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 22))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            TextRule(width: 30, height: 4, opacity: 0.9)
        }
    }
}

private struct DockStrip: View {
    private static let tiles: [Color] = [.mint, .orange, .teal, .red, .yellow, .cyan]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.tiles, id: \.self) { tile in
                RoundedRectangle(cornerRadius: 6)
                    .fill(tile.gradient)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(5)
        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 11))
    }
}

/// One line of stand-in text.
private struct TextRule: View {
    let width: CGFloat
    let height: CGFloat
    var opacity: CGFloat = 0.85

    var body: some View {
        Capsule()
            .fill(.foreground.opacity(opacity))
            .frame(width: width, height: height)
    }
}

#Preview("Preview Wallpaper") {
    PreviewWallpaper()
}
