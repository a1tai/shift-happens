import Foundation

/// Starts the app in the background at login via ~/Library/LaunchAgents, so the remaps and
/// shortcuts come back after every reboot. The app then lives in the menu bar.
enum LaunchAgent {
    static let label = "io.github.a1tai.ShiftHappens.agent"
    /// The label before the rename.
    static let oldLabel = "com.keybindingapp.agent"
    static let backgroundArgument = "--background"

    static var plistURL: URL { plistURL(for: label) }

    private static func plistURL(for label: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// The plist points at the current executable; if the app was moved, it has to be rewritten.
    static var pointsAtCurrentApp: Bool {
        guard let dict = NSDictionary(contentsOf: plistURL),
              let args = dict["ProgramArguments"] as? [String] else { return false }
        return args.first == Bundle.main.executablePath
    }

    static func enable() throws {
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, backgroundArgument],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written only: launchd picks it up at the next login. Loading it now would start a second copy.
        try data.write(to: plistURL, options: .atomic)
    }

    static func disable() throws {
        if isEnabled { try FileManager.default.removeItem(at: plistURL) }
    }

    /// Keeps the plist pointing at this copy of the app after it was moved (e.g. into /Applications).
    /// A plist this app wrote under its old label is replaced by one under the new label.
    static func refreshIfNeeded() {
        let old = plistURL(for: oldLabel)
        if let dict = NSDictionary(contentsOf: old), dict["Label"] as? String == oldLabel,
           (dict["ProgramArguments"] as? [String])?.last == backgroundArgument {
            try? FileManager.default.removeItem(at: old)
            try? enable()
        }
        if isEnabled && !pointsAtCurrentApp { try? enable() }
    }
}
