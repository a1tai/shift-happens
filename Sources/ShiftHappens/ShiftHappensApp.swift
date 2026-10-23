import AppKit
import SwiftUI

@main
struct ShiftHappensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            let icon = state.config.enabled ? "keyboard.fill" : "keyboard"
            if state.config.showsInputLanguage, let language = state.currentLayoutLabel {
                // One Text with the symbol inside: a menu bar label shows a single view.
                Text("\(Image(systemName: icon)) \(language)")
            } else {
                Image(systemName: icon)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showWindowNotification = Notification.Name("io.github.a1tai.ShiftHappens.showWindow")
    #if DEBUG
    /// Same as the menu item; lets the Emoji & Symbols action be checked without clicking the menu.
    /// Debug builds only: in a release, other programs must not be able to make the app send keys.
    static let showEmojiNotification = Notification.Name("io.github.a1tai.ShiftHappens.showEmojiAndSymbols")
    #endif

    /// NSApp.delegate is SwiftUI's wrapper, so views reach this object through here.
    static private(set) weak var shared: AppDelegate?

    private var window: NSWindow?
    /// Termination signals skip applicationWillTerminate; these handlers clean up the same way first.
    private var signalSources: [DispatchSourceSignal] = []
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
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        DebugSnapshot.runSelfTestIfRequested()
        DebugSnapshot.runAppTestIfRequested()
        DebugSnapshot.runShortcutTestIfRequested()
        Self.shared = self
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showEmojiNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppState.shared.showEmojiAndSymbols() }
        }
        #endif
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showWindowNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppDelegate.shared?.showMainWindow() }
        }
        AppState.shared.start()
        if !startedInBackground { showMainWindow() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave macOS's own shortcuts switched off, or a macro's keys held down.
        SystemShortcuts.restore()
        AppState.shared.combos.macros.cancelAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar: the shortcuts need the app alive.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    var mainWindowHeight: CGFloat? { window?.frame.height }

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
