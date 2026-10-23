import Foundation

/// macOS's own keyboard shortcuts, to pick as a combo's output instead of remembering them. Only default
/// shortcuts the app can send: none with fn, Eject or the power key.
struct SystemShortcut: Identifiable, Hashable {
    let category: String
    let name: String
    let chord: KeyChord

    var id: String { category + "/" + name }

    static let categories = ["Screenshots", "System", "Windows", "Finder", "Text", "Accessibility"]

    static let all: [SystemShortcut] = {
        func s(_ category: String, _ name: String, _ key: UInt16, _ mods: ModifierSet) -> SystemShortcut {
            SystemShortcut(category: category, name: name, chord: KeyChord(keyCode: key, modifiers: mods))
        }
        let shift: ModifierSet = .shift, cmd: ModifierSet = .command, ctrl: ModifierSet = .control, opt: ModifierSet = .option
        return [
            s("Screenshots", "Screenshot of the screen", 0x14, [cmd, shift]),
            s("Screenshots", "Screenshot of an area", 0x15, [cmd, shift]),
            s("Screenshots", "Screenshot and recording options", 0x17, [cmd, shift]),
            s("Screenshots", "Screen to the clipboard", 0x14, [ctrl, cmd, shift]),
            s("Screenshots", "Area to the clipboard", 0x15, [ctrl, cmd, shift]),

            s("System", "Lock Screen", 0x0C, [ctrl, cmd]),
            s("System", "Force Quit", 0x35, [opt, cmd]),
            s("System", "Log Out", 0x0C, [shift, cmd]),
            s("System", "Spotlight", 0x31, cmd),
            s("System", "Full Screen", 0x03, [ctrl, cmd]),

            s("Windows", "Hide Others", 0x04, [opt, cmd]),
            s("Windows", "Minimize All Windows of the App", 0x2E, [opt, cmd]),
            s("Windows", "Mission Control", 0x7E, ctrl),
            s("Windows", "App Windows", 0x7D, ctrl),
            s("Windows", "Previous Desktop", 0x7B, ctrl),
            s("Windows", "Next Desktop", 0x7C, ctrl),

            s("Finder", "Show Hidden Files", 0x2F, [shift, cmd]),
            s("Finder", "Go to Folder", 0x05, [shift, cmd]),
            s("Finder", "Downloads", 0x25, [opt, cmd]),
            s("Finder", "Applications", 0x00, [shift, cmd]),
            s("Finder", "Desktop", 0x02, [shift, cmd]),
            s("Finder", "Home", 0x04, [shift, cmd]),
            s("Finder", "Empty Trash", 0x33, [shift, cmd]),
            s("Finder", "Delete Immediately", 0x33, [opt, cmd]),
            s("Finder", "Get Info", 0x22, cmd),

            s("Text", "Paste and Match Style", 0x09, [opt, shift, cmd]),
            s("Text", "Emoji & Symbols", 0x31, [ctrl, cmd]),
            s("Text", "Delete to Start of Line", 0x33, cmd),
            s("Text", "Delete Previous Word", 0x33, opt),

            s("Accessibility", "Zoom On or Off", 0x1C, [opt, cmd]),
            s("Accessibility", "Invert Colors", 0x1C, [ctrl, opt, cmd]),
            s("Accessibility", "VoiceOver", 0x60, cmd),
        ]
    }()

    private static let byChord: [KeyChord: SystemShortcut] =
        Dictionary(all.map { ($0.chord, $0) }, uniquingKeysWith: { first, _ in first })

    /// The catalog entry a combo's output is, if any.
    static func named(_ chord: KeyChord) -> SystemShortcut? { byChord[chord] }

    /// Entries whose name, category or keys contain `text`, in catalog order.
    static func search(_ text: String) -> [SystemShortcut] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)
                || $0.chord.display.localizedCaseInsensitiveContains(query)
        }
    }
}
