import AppKit
import ApplicationServices
import IOKit.hid

/// The two privacy permissions the app uses.
enum Permission: String, CaseIterable, Identifiable {
    case inputMonitoring, accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        }
    }

    var reason: String {
        switch self {
        case .inputMonitoring: return "To see key codes, light up pressed keys and tell keyboards apart."
        case .accessibility: return "For Combos and the Layout Fixer. Plain remaps work without it."
        }
    }

    /// The service name `tccutil` uses.
    fileprivate var tccService: String {
        switch self {
        case .inputMonitoring: return "ListenEvent"
        case .accessibility: return "Accessibility"
        }
    }

    fileprivate var settingsURL: String {
        switch self {
        case .inputMonitoring: return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

/// Checks and requests permissions. macOS shows its own dialog only while a permission is undecided;
/// after that the app can only send the user to System Settings.
enum Permissions {
    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .inputMonitoring: return HIDMonitor.hasAccess
        case .accessibility: return ComboEngine.hasAccess
        }
    }

    /// True once the app has asked macOS for this permission (with this build's signature or an older one).
    static func wasRequested(_ permission: Permission) -> Bool {
        UserDefaults.standard.bool(forKey: requestedKey(permission)) || DebugSnapshot.assumesRequested
    }

    /// Shows macOS's own dialog if it hasn't been shown yet, otherwise opens the right System Settings pane.
    static func request(_ permission: Permission) {
        guard !isGranted(permission) else { return }
        let alreadyAsked = wasRequested(permission)
        UserDefaults.standard.set(true, forKey: requestedKey(permission))
        switch permission {
        case .inputMonitoring:
            // Unknown means macOS has never asked: then it shows its dialog. Denied means it never will again.
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
                HIDMonitor.requestAccess()
            } else {
                openSettings(for: permission)
            }
        case .accessibility:
            // Also adds the app to the list in System Settings, switched off.
            ComboEngine.requestAccess()
            if alreadyAsked { openSettings(for: permission) }
        }
    }

    static func openSettings(for permission: Permission) {
        if let url = URL(string: permission.settingsURL) { NSWorkspace.shared.open(url) }
    }

    /// Forgets macOS's earlier decision for this app and asks again. Needed when System Settings shows the app
    /// as allowed but the permission still doesn't work: the entry belongs to an older build with another signature.
    static func resetAndRequest(_ permission: Permission) {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            openSettings(for: permission)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", permission.tccService, bundleID]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                UserDefaults.standard.set(false, forKey: requestedKey(permission))
                request(permission)
            }
        }
        do {
            try process.run()
        } catch {
            openSettings(for: permission)
        }
    }

    /// Starts a fresh copy of the app and quits this one. Input Monitoring only takes effect after a relaunch.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this copy to quit: a second copy that finds the first one still running just exits.
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func requestedKey(_ permission: Permission) -> String {
        "requested.\(permission.rawValue)"
    }
}
