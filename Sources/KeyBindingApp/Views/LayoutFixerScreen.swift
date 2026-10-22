import SwiftUI

/// Settings for fixing text typed in the wrong keyboard layout.
struct LayoutFixerScreen: View {
    @EnvironmentObject private var state: AppState

    private var settings: Binding<LayoutFixerSettings> { $state.config.layoutFixer }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                title: "Layout Fixer",
                subtitle: "Typed a word in the wrong layout? Press one key to retype it in the right one."
            ) {
                EmptyView()
            }
            .padding([.horizontal, .top], 24)

            Form {
                Section {
                    Toggle("Fix text typed in the wrong layout", isOn: settings.enabled)
                    Picker("Trigger key", selection: settings.trigger) {
                        ForEach(LayoutTrigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    Toggle("Show the current layout in the menu bar", isOn: settings.showsLayoutInMenuBar)
                    warnings
                }

                Section("How to use") {
                    HowToRow(icon: "character.cursor.ibeam", title: "Fix the last word",
                             details: "Type a word, then press and release the trigger key on its own. "
                                + "The word is retyped in the next layout and the layout switches.")
                    HowToRow(icon: "character.textbox", title: "Fix a selection",
                             details: "Select text and press the trigger key. The layout it was typed in is detected.")
                    HowToRow(icon: "globe", title: "Switch layout",
                             details: "With nothing typed or selected, the trigger key switches to the next layout.")
                    HowToRow(icon: "arrow.uturn.backward", title: "Undo",
                             details: "Press the trigger key again to convert back.")
                    Text("Only a lone press counts, so shortcuts with the trigger key (like ⌥← or your combos) keep working. "
                         + "The key is checked after your remaps: if Win and Alt are swapped, Option is the Win key.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if state.inputSources.isEmpty {
                        Text("No keyboard layouts found.").foregroundStyle(.secondary)
                    }
                    ForEach(state.inputSources) { source in
                        HStack {
                            Text(source.shortLabel)
                                .font(.callout.monospaced().weight(.semibold))
                                .frame(width: 34, height: 22)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                            Text(source.name)
                            Spacer()
                            if source.id == state.currentInputSourceID {
                                Label("Current", systemImage: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                } header: {
                    Text("Keyboard layouts")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("With three or more layouts, each press moves to the next one in this list.")
                        // A literal, so SwiftUI renders the Markdown links.
                        Text("Based on [Perekluk](https://github.com/abaskalov/perekluk) by [abaskalov](https://github.com/abaskalov) (MIT License).")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if state.config.layoutFixer.enabled && !state.accessibilityGranted {
            WarningRow(text: "Needs Accessibility access to watch typing and replace text.",
                       button: "Allow…", action: { Permissions.request(.accessibility) })
        }
        if state.inputSources.count < 2 {
            WarningRow(text: "Only one keyboard layout is enabled. Add another in System Settings → Keyboard → Text Input.",
                       button: "Keyboard Settings", action: LayoutFixer.openKeyboardSettings)
        }
        if state.config.layoutFixer.trigger == .fn && !LayoutFixer.globeKeyDoesNothing {
            WarningRow(text: "macOS also reacts to a lone 🌐 press. Set “Press 🌐 key to” to Do Nothing in Keyboard settings.",
                       button: "Keyboard Settings", action: LayoutFixer.openKeyboardSettings)
        }
        if state.config.layoutFixer.trigger == .capsLock {
            WarningRow(text: "Caps Lock no longer turns capitals on while it is the trigger key.",
                       button: nil, action: {})
        }
    }
}

private struct HowToRow: View {
    let icon: String
    let title: String
    let details: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(details).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WarningRow: View {
    let text: String
    let button: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            if let button { Button(button, action: action) }
        }
    }
}
