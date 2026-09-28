import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let info = AppInfo.current
    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            AppIconView()
                .frame(width: 96, height: 96)

            Text(info.name)
                .font(.title2)
                .bold()

            Button(action: copyVersion) {
                ZStack {
                    // Both stay laid out, so the window keeps its size as the text swaps.
                    VStack(spacing: 2) {
                        Text(.aboutVersion(info.version))
                        Text(.aboutBuild(info.build, info.commitHash))
                    }
                    .opacity(didCopy ? 0 : 1)

                    Text(.aboutCopied)
                        .opacity(didCopy ? 1 : 0)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .pointerStyle(.link)
            .focusable(false)
            .multilineTextAlignment(.center)
            .font(.callout)
            .help(Text(.aboutCopyHelp))
            .animation(.easeInOut(duration: 0.15), value: didCopy)

            Button(.close) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 260)
        .fixedSize()
    }

    private func copyVersion() {
        let summary = "\(info.name) \(info.version) (\(info.commitHash))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)

        didCopy = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

/// An app-icon set has no SwiftUI asset symbol on macOS, hence AppKit's.
private struct AppIconView: View {
    var body: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AboutView()
}
