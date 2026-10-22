import AppKit

/// An application a combo or macro step opens. Found by bundle identifier, so it still works after the
/// app moves or updates; the last known path is the fallback.
struct AppTarget: Codable, Hashable {
    var bundleID: String
    var path: String
    var name: String
    /// Combo only: pressing the trigger while the app is already in front hides it.
    var hidesIfFrontmost = false

    init(bundleID: String, path: String, name: String, hidesIfFrontmost: Bool = false) {
        self.bundleID = bundleID
        self.path = path
        self.name = name
        self.hidesIfFrontmost = hidesIfFrontmost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? bundleID
        hidesIfFrontmost = try c.decodeIfPresent(Bool.self, forKey: .hidesIfFrontmost) ?? false
    }

    enum Limits {
        static let bundleID = 255
        static let path = 1_024
        static let name = 200
    }

    /// A bundle identifier made of letters, digits, dots, dashes and underscores; an absolute path to an
    /// .app bundle (or none). Anything else in a config file is dropped, never opened.
    var isValid: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard !bundleID.isEmpty, bundleID.count <= Limits.bundleID,
              bundleID.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        guard path.isEmpty || (path.count <= Limits.path && path.hasPrefix("/") && path.hasSuffix(".app")) else { return false }
        return name.count <= Limits.name
    }

    func sanitized() -> AppTarget? {
        var target = self
        target.name = String(name.prefix(Limits.name))
        return target.isValid ? target : nil
    }
}

/// Opens applications for combos and macros. Only .app bundles, only through NSWorkspace: nothing is
/// ever run through a shell, and no other kind of file is opened.
enum AppLauncher {
    /// Where the app picker starts and looks.
    static let folders = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"]

    /// The target for an .app bundle the user picked or dropped.
    static func target(for url: URL) -> AppTarget? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppTarget(bundleID: id, path: url.path, name: name).sanitized()
    }

    /// The app's current location: by bundle identifier, else the saved path if it is still that app.
    static func url(for target: AppTarget) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID) { return url }
        guard !target.path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: target.path)
        return Bundle(url: url)?.bundleIdentifier == target.bundleID ? url : nil
    }

    static func icon(for target: AppTarget) -> NSImage {
        if let url = url(for: target) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// Brings the app to the front, launching it if needed; with `hidesIfFrontmost`, hides it when it is
    /// already in front. Main thread only.
    static func open(_ target: AppTarget, allowsHide: Bool = true) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first
        if let running, running.isActive, allowsHide, target.hidesIfFrontmost {
            running.hide()
            return
        }
        running?.unhide()
        guard target.isValid, let url = url(for: target) else {
            NSLog("Shift Happens: can't find the app \(target.bundleID)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Also activates an app that is already running, which a background app can't do on its own.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("Shift Happens: opening \(target.bundleID) failed: \(error.localizedDescription)") }
        }
    }

    /// For macros, off the main thread: opens the app, then waits until it is in front (at most `timeout`).
    static func openAndWait(_ target: AppTarget, timeout: TimeInterval = 3) {
        DispatchQueue.main.sync { open(target, allowsHide: false) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let front = DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            if front == target.bundleID { return }
            usleep(50_000)
        }
    }
}
