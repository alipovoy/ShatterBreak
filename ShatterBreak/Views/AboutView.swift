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
                if didCopy {
                    Text(.aboutCopied)
                } else {
                    VStack(spacing: 2) {
                        Text(.aboutVersion(info.version))
                        Text(.aboutBuild(info.build, info.commitHash))
                    }
                }
            }
            .buttonStyle(.link)
            .multilineTextAlignment(.center)
            .font(.callout)
            .help(Text(.aboutCopyHelp))

            Button(.close) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 260)
        .fixedSize()
    }

    /// Copies a single-line version summary to the clipboard and briefly swaps the
    /// link text to a confirmation, reverting after a short delay.
    private func copyVersion() {
        let summary = "\(info.name) \(info.version) (\(info.commitHash))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)

        didCopy = true
        // Restart the timer on repeated clicks so the confirmation always lingers.
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

/// The running application's icon, identical to the artwork in the asset catalog.
///
/// An app-icon *set* is not exposed as a SwiftUI `Image(name:)` asset symbol on
/// macOS, so the AppKit application icon is used instead.
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
