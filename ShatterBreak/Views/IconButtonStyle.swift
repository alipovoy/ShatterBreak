import SwiftUI

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .foregroundStyle(Color.accentColor)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.05), value: configuration.isPressed)
    }
}

#Preview("IconButtonStyle") {
    HStack(spacing: 20) {
        Button("Preferences", systemImage: "gearshape", action: { })
        Button("About", systemImage: "info.circle", action: { })
        Button("Statistics", systemImage: "chart.bar", action: { })
    }
    .labelStyle(.iconOnly)
    .buttonStyle(IconButtonStyle())
    .padding()
}
