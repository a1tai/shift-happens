import AppKit
import SwiftUI

/// The menu under the keyboard icon in the menu bar.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Toggle("Привязки включены", isOn: $state.config.enabled)
        Text("\(state.config.remaps.filter(\.enabled).count) переназначений · \(state.config.combos.filter(\.enabled).count) комбинаций")
        if !state.inputMonitoringGranted || (!state.accessibilityGranted && !state.config.combos.isEmpty) {
            Text("⚠︎ Не хватает разрешений, откройте окно")
        }
        Divider()
        Button("Открыть KeyBindingApp…") { AppDelegate.shared?.showMainWindow() }
            .keyboardShortcut("o")
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
