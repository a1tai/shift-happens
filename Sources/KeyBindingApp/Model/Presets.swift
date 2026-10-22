import Foundation

/// Ready-made sets that make a Windows keyboard behave like a Mac one.
enum Preset: String, CaseIterable, Identifiable {
    case swapWinAlt, printScreen, homeEnd, ctrlShortcuts, mouseBackForward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swapWinAlt: return "Swap Win and Alt"
        case .printScreen: return "Print Screen → screenshot of an area"
        case .homeEnd: return "Home and End like in Windows"
        case .ctrlShortcuts: return "Ctrl+C, V, X, Z, A, S, F like in Windows"
        case .mouseBackForward: return "Mouse Back/Forward in Safari and Finder"
        }
    }

    var details: String {
        switch self {
        case .swapWinAlt:
            return "Alt becomes ⌘ Command and Win becomes ⌥ Option, matching the Mac key layout. Only for the selected keyboard."
        case .printScreen:
            return "PrtSc sends ⌘⇧4, ⇧PrtSc sends ⌘⇧3 (whole screen)."
        case .homeEnd:
            return "Home/End go to the start and end of the line, select with ⇧, and go to the start and end of the document with Ctrl."
        case .ctrlShortcuts:
            return "Ctrl+letter sends ⌘+letter. While this preset is on, Ctrl+C no longer interrupts programs in Terminal."
        case .mouseBackForward:
            return "Mouse button 4 sends ⌘[ (back) and button 5 sends ⌘] (forward), which Safari and Finder understand."
        }
    }

    /// Applies the preset. Remaps go to `device` (nil = every keyboard).
    func apply(to state: AppState, device: DeviceRef?) {
        switch self {
        case .swapWinAlt:
            let pairs: [(UInt32, UInt32)] = [(0xE2, 0xE3), (0xE3, 0xE2), (0xE6, 0xE7), (0xE7, 0xE6)]
            for (from, to) in pairs {
                state.save(KeyRemap(
                    from: HIDUsage(page: HIDPage.keyboard, usage: from),
                    to: HIDUsage(page: HIDPage.keyboard, usage: to),
                    device: device
                ))
            }
        case .printScreen:
            combo(state, 0x69, [], 0x15, [.command, .shift], "Screenshot of area")
            combo(state, 0x69, .shift, 0x14, [.command, .shift], "Screenshot of screen")
        case .homeEnd:
            combo(state, 0x73, [], 0x7B, .command, "Start of line")
            combo(state, 0x77, [], 0x7C, .command, "End of line")
            combo(state, 0x73, .shift, 0x7B, [.command, .shift], "Select to start of line")
            combo(state, 0x77, .shift, 0x7C, [.command, .shift], "Select to end of line")
            combo(state, 0x73, .control, 0x7E, .command, "Start of document")
            combo(state, 0x77, .control, 0x7D, .command, "End of document")
        case .ctrlShortcuts:
            let letters: [(UInt16, String)] = [(0x08, "Copy"), (0x09, "Paste"), (0x07, "Cut"),
                                               (0x06, "Undo"), (0x00, "Select all"), (0x01, "Save"),
                                               (0x03, "Find")]
            for (code, note) in letters {
                combo(state, code, .control, code, .command, note)
            }
            combo(state, 0x10, .control, 0x06, [.command, .shift], "Redo")
        case .mouseBackForward:
            state.save(ComboBinding(trigger: .mouse(3), output: KeyChord(keyCode: 0x21, modifiers: .command), note: "Back"))
            state.save(ComboBinding(trigger: .mouse(4), output: KeyChord(keyCode: 0x1E, modifiers: .command), note: "Forward"))
        }
    }

    private func combo(_ state: AppState, _ key: UInt16, _ mods: ModifierSet,
                       _ outKey: UInt16, _ outMods: ModifierSet, _ note: String) {
        state.save(ComboBinding(
            trigger: KeyChord(keyCode: key, modifiers: mods),
            output: KeyChord(keyCode: outKey, modifiers: outMods),
            note: note
        ))
    }
}
