import AppKit
import SwiftUI

@main
struct KeyBindingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Image(systemName: state.config.enabled ? "keyboard.fill" : "keyboard")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showWindowNotification = Notification.Name("com.keybindingapp.showWindow")

    /// NSApp.delegate is SwiftUI's wrapper, so views reach this object through here.
    static private(set) weak var shared: AppDelegate?

    private var window: NSWindow?
    private let startedInBackground = CommandLine.arguments.contains(LaunchAgent.backgroundArgument)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Only one copy may own the event tap and hidutil. A second launch just shows the first one's window.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                if !startedInBackground {
                    DistributedNotificationCenter.default().postNotificationName(
                        Self.showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
                }
                exit(0)
            }
        }
        NSApp.setActivationPolicy(startedInBackground ? .accessory : .regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugSnapshot.runSelfTestIfRequested()
        Self.shared = self
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showWindowNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppDelegate.shared?.showMainWindow() }
        }
        AppState.shared.start()
        if !startedInBackground { showMainWindow() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave macOS's own shortcuts switched off.
        SystemShortcuts.restore()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar: the shortcuts need the app alive.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Shift Happens"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 560)
            window.contentViewController = NSHostingController(
                rootView: ContentView().environmentObject(AppState.shared)
            )
            window.setFrameAutosaveName("MainWindow")
            if !window.setFrameUsingName("MainWindow") { window.center() }
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { _ in
                AppState.shared.setWindowVisible(window.occlusionState.contains(.visible))
            }
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                AppState.shared.setWindowVisible(false)
                // Back to a menu-bar-only app: no Dock icon while the window is closed.
                NSApp.setActivationPolicy(.accessory)
            }
            self.window = window
            DebugSnapshot.runIfRequested(window: window)
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        AppState.shared.setWindowVisible(true)
        NSApp.activate(ignoringOtherApps: true)
    }
}
