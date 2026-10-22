import AppKit

/// Shortcuts into System Settings > Privacy & Security.
enum Permissions {
    static func openInputMonitoring() {
        HIDMonitor.requestAccess()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibility() {
        ComboEngine.requestAccess()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
