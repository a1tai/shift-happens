import AppKit
import SwiftUI

/// The menu under the keyboard icon in the menu bar.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Toggle("Bindings on", isOn: $state.config.enabled)
        Text(counted(state.config.remaps.filter(\.enabled).count, "remap") + " · "
             + counted(state.config.combos.filter(\.enabled).count, "combo"))
        Toggle("Layout Fixer", isOn: $state.config.layoutFixer.enabled)
        if !state.inputMonitoringGranted
            || (!state.accessibilityGranted && (!state.config.combos.isEmpty || state.config.layoutFixer.enabled)) {
            Text("⚠︎ Missing permissions, open the window")
        }
        if state.inputSources.count > 1 {
            Divider()
            Picker("Keyboard Layout", selection: Binding(
                get: { state.currentInputSourceID ?? "" },
                set: { state.selectInputSource($0) }
            )) {
                ForEach(state.inputSources) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .pickerStyle(.inline)
        }
        Divider()
        Button("Open Shift Happens…") { AppDelegate.shared?.showMainWindow() }
            .keyboardShortcut("o")
        Divider()
        Button("Quit Shift Happens") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
