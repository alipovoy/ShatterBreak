import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let info = AppInfo.current

    var body: some View {
        VStack(spacing: 16) {
            AppIconView()
                .frame(width: 96, height: 96)

            Text(info.name)
                .font(.title2)
                .bold()

            VStack(spacing: 4) {
                LabeledContent {
                    Text(info.version)
                } label: {
                    Text(.aboutVersionLabel)
                }
                LabeledContent {
                    Text(info.build)
                } label: {
                    Text(.aboutBuildLabel)
                }
                LabeledContent {
                    Text(info.commitHash)
                        .monospaced()
                } label: {
                    Text(.aboutCommitLabel)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .labeledContentStyle(.about)

            Button(.close) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 260)
        .fixedSize()
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

/// Lays out each metadata row with the label and value side by side and the
/// value trailing-aligned, keeping the small list visually tidy.
private struct AboutLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
        }
    }
}

private extension LabeledContentStyle where Self == AboutLabeledContentStyle {
    static var about: AboutLabeledContentStyle { AboutLabeledContentStyle() }
}

#Preview {
    AboutView()
}
