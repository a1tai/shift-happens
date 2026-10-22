import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Picks an application: a button that opens a panel limited to apps, or an .app dropped onto it.
/// Shows the chosen app's icon and name.
struct AppPickerField: View {
    @Binding var app: AppTarget?
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            if let app {
                AppLabel(app: app)
            } else {
                Text("No app chosen").foregroundStyle(.secondary)
            }
            Button(app == nil ? "Choose App…" : "Change…", action: choose)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isTargeted ? 2 : 1))
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let target = AppLauncher.target(for: url) else { return }
                DispatchQueue.main.async { app = target.keepingOptions(of: app) }
            }
            return true
        }
        .help("Choose an app, or drop one here from the Finder")
    }

    private func choose() {
        guard let target = AppLauncher.choose() else { return }
        app = target.keepingOptions(of: app)
    }
}

extension AppLauncher {
    /// Asks for an app in an open panel limited to applications.
    static func choose() -> AppTarget? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: folders[0])
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return target(for: url)
    }
}

/// An app's icon and name.
struct AppLabel: View {
    let app: AppTarget
    var iconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: AppLauncher.icon(for: app))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            Text(app.name).lineLimit(1)
        }
    }
}

private extension AppTarget {
    /// A newly picked app keeps the options set for the previous one.
    func keepingOptions(of old: AppTarget?) -> AppTarget {
        var target = self
        target.hidesIfFrontmost = old?.hidesIfFrontmost ?? false
        return target
    }
}
