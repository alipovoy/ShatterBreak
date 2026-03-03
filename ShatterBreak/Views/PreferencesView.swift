import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    // Using @AppStorage to automatically persist preferences to UserDefaults
    @AppStorage("playSound") private var playSound: Bool = true
    @AppStorage("effectType") private var effectType: EffectType = .shatter

    var body: some View {
        VStack(spacing: 20) {
            Form {
                Section("General Settings") {
                    Toggle("Play Sound", isOn: $playSound)

                    Picker("Effect Type", selection: $effectType) {
                        ForEach(EffectType.allCases) { effect in
                            Text(effect.rawValue).tag(effect)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .headerProminence(.increased)
            }
            .formStyle(.grouped)
        }
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding([.trailing, .bottom])
    }
}


#Preview {
    PreferencesView()
}
