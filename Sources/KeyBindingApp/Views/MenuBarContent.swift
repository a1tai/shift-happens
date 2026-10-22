import AppKit
import SwiftUI

/// The menu under the keyboard icon in the menu bar.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Toggle("Bindings on", isOn: $state.config.enabled)
        Text(counted(state.config.remaps.filter(\.enabled).count, "remap") + " · "
             + counted(state.config.combos.filter(\.enabled).count, "combo"))
        if !state.inputMonitoringGranted || (!state.accessibilityGranted && !state.config.combos.isEmpty) {
            Text("⚠︎ Missing permissions, open the window")
        }
        Divider()
        Button("Open KeyBindingApp…") { AppDelegate.shared?.showMainWindow() }
            .keyboardShortcut("o")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
