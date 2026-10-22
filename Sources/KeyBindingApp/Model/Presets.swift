import Foundation

/// Ready-made sets that make a Windows keyboard behave like a Mac one.
enum Preset: String, CaseIterable, Identifiable {
    case swapWinAlt, printScreen, homeEnd, ctrlShortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swapWinAlt: return "Поменять местами Win и Alt"
        case .printScreen: return "Print Screen → снимок области экрана"
        case .homeEnd: return "Home и End как в Windows"
        case .ctrlShortcuts: return "Ctrl+C, V, X, Z, A, S, F как в Windows"
        }
    }

    var details: String {
        switch self {
        case .swapWinAlt:
            return "Alt будет ⌘ Command, а Win станет ⌥ Option, как расположено на клавиатуре Mac. Только для выбранной клавиатуры."
        case .printScreen:
            return "PrtSc отправляет ⌘⇧4, ⇧PrtSc отправляет ⌘⇧3 (весь экран)."
        case .homeEnd:
            return "Home/End переходят в начало и конец строки, с ⇧ выделяют, с Ctrl идут в начало и конец документа."
        case .ctrlShortcuts:
            return "Ctrl+буква отправляет ⌘+буква. В Терминале Ctrl+C перестанет прерывать программы, пока набор включён."
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
            combo(state, 0x69, [], 0x15, [.command, .shift], "Снимок области")
            combo(state, 0x69, .shift, 0x14, [.command, .shift], "Снимок экрана")
        case .homeEnd:
            combo(state, 0x73, [], 0x7B, .command, "Начало строки")
            combo(state, 0x77, [], 0x7C, .command, "Конец строки")
            combo(state, 0x73, .shift, 0x7B, [.command, .shift], "Выделить до начала строки")
            combo(state, 0x77, .shift, 0x7C, [.command, .shift], "Выделить до конца строки")
            combo(state, 0x73, .control, 0x7E, .command, "Начало документа")
            combo(state, 0x77, .control, 0x7D, .command, "Конец документа")
        case .ctrlShortcuts:
            let letters: [(UInt16, String)] = [(0x08, "Копировать"), (0x09, "Вставить"), (0x07, "Вырезать"),
                                               (0x06, "Отменить"), (0x00, "Выделить всё"), (0x01, "Сохранить"),
                                               (0x03, "Найти")]
            for (code, note) in letters {
                combo(state, code, .control, code, .command, note)
            }
            combo(state, 0x10, .control, 0x06, [.command, .shift], "Повторить")
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
