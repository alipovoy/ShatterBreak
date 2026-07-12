import SwiftUI

/// Visual chooser for the break-screen effect: one selectable thumbnail per
/// ``EffectType``, so the options read by look rather than by name.
struct EffectCardPicker: View {
    @Binding var selection: EffectType

    var body: some View {
        HStack(spacing: 12) {
            ForEach(EffectType.allCases) { effect in
                EffectCard(effect: effect, isSelected: effect == selection) {
                    selection = effect
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct EffectCard: View {
    let effect: EffectType
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: 108, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(effect.displayName)
                    .font(.callout)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A stylized miniature of the effect over a mock desktop gradient.
    private var thumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.65), Color.purple.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            switch effect {
            case .shatter:
                Image(systemName: "burst")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            case .fogged:
                Rectangle()
                    .fill(.ultraThinMaterial)
                Image(systemName: "cloud.fog")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            case .dimmed:
                Color.black.opacity(0.55)
                Image(systemName: "moon.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

#Preview("EffectCardPicker") {
    @Previewable @State var selection: EffectType = .shatter
    Form {
        EffectCardPicker(selection: $selection)
    }
    .formStyle(.grouped)
}
