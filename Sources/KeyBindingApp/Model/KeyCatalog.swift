import Foundation

/// Usage pages that matter for keyboards.
enum HIDPage {
    static let keyboard: UInt32 = 0x07
    static let consumer: UInt32 = 0x0C
    static let appleVendorTopCase: UInt32 = 0xFF
}

/// One key from the HID tables, with how macOS sees it (virtual key code), when it does.
struct KeyDef: Hashable, Identifiable {
    let page: UInt32
    let usage: UInt32
    /// Full name shown in lists.
    let name: String
    /// Short label drawn on a key cap.
    let label: String
    /// macOS virtual key code (kVK_*) produced by this key without any remapping.
    let macKeyCode: UInt16?
    let category: Category

    enum Category: String, CaseIterable {
        case letters = "Буквы"
        case digits = "Цифры"
        case symbols = "Символы"
        case editing = "Управление"
        case navigation = "Навигация"
        case function = "F-клавиши"
        case modifiers = "Модификаторы"
        case keypad = "Цифровой блок"
        case media = "Медиа и система"
    }

    var id: UInt64 { hid.hidutilValue }
    var hid: HIDUsage { HIDUsage(page: page, usage: usage) }
}

enum KeyCatalog {
    static let all: [KeyDef] = build()

    private static let byHID: [UInt64: KeyDef] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let byMacKeyCode: [UInt16: KeyDef] = {
        var map: [UInt16: KeyDef] = [:]
        for key in all {
            if let code = key.macKeyCode, map[code] == nil { map[code] = key }
        }
        return map
    }()

    static func key(for usage: HIDUsage) -> KeyDef? { byHID[usage.hidutilValue] }
    static func key(forMacKeyCode code: UInt16) -> KeyDef? { byMacKeyCode[code] }

    static func name(for usage: HIDUsage) -> String {
        key(for: usage)?.name ?? String(format: "HID 0x%02X/0x%02X", usage.page, usage.usage)
    }

    static func label(for usage: HIDUsage) -> String {
        key(for: usage)?.label ?? String(format: "%02X", usage.usage)
    }

    /// Name of a macOS virtual key code, used for key combinations.
    static func name(forMacKeyCode code: UInt16) -> String {
        key(forMacKeyCode: code)?.label ?? String(format: "Код %d", code)
    }

    /// Keys that make sense as a remap source (physical keyboard keys).
    static var sources: [KeyDef] { all.filter { $0.page == HIDPage.keyboard } }
    /// Keys that make sense as a remap target.
    static var targets: [KeyDef] { all }
    /// Keys that macOS can emit as virtual key codes (for combinations).
    /// Each macOS key code appears once (e.g. Print Screen and F13 are the same code).
    static let chordKeys: [KeyDef] = {
        var seen = Set<UInt16>()
        return all.filter { key in
            guard let code = key.macKeyCode, key.category != .modifiers else { return false }
            return seen.insert(code).inserted
        }
    }()

    // MARK: - Table

    private static func build() -> [KeyDef] {
        var keys: [KeyDef] = []
        func k(_ usage: UInt32, _ name: String, _ label: String, _ mac: UInt16?, _ cat: KeyDef.Category, page: UInt32 = HIDPage.keyboard) {
            keys.append(KeyDef(page: page, usage: usage, name: name, label: label, macKeyCode: mac, category: cat))
        }

        // Letters a..z (HID 0x04...0x1D)
        let letterCodes: [UInt16] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                     0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (i, scalar) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            let s = String(scalar)
            k(0x04 + UInt32(i), s, s, letterCodes[i], .letters)
        }
        // Digits 1..9, 0 (HID 0x1E...0x27)
        let digitCodes: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (i, s) in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].enumerated() {
            k(0x1E + UInt32(i), s, s, digitCodes[i], .digits)
        }

        k(0x28, "Enter", "Enter", 0x24, .editing)
        k(0x29, "Escape", "Esc", 0x35, .editing)
        k(0x2A, "Backspace", "⌫", 0x33, .editing)
        k(0x2B, "Tab", "Tab", 0x30, .editing)
        k(0x2C, "Пробел", "Space", 0x31, .editing)
        k(0x2D, "Минус -", "-", 0x1B, .symbols)
        k(0x2E, "Равно =", "=", 0x18, .symbols)
        k(0x2F, "Скобка [", "[", 0x21, .symbols)
        k(0x30, "Скобка ]", "]", 0x1E, .symbols)
        k(0x31, "Обратный слэш \\", "\\", 0x2A, .symbols)
        k(0x32, "Non-US # (ISO)", "#", 0x2A, .symbols)
        k(0x33, "Точка с запятой ;", ";", 0x29, .symbols)
        k(0x34, "Апостроф '", "'", 0x27, .symbols)
        k(0x35, "Гравис `", "`", 0x32, .symbols)
        k(0x36, "Запятая ,", ",", 0x2B, .symbols)
        k(0x37, "Точка .", ".", 0x2F, .symbols)
        k(0x38, "Слэш /", "/", 0x2C, .symbols)
        k(0x39, "Caps Lock", "Caps", 0x39, .modifiers)

        let fCodes: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for i in 0..<12 { k(0x3A + UInt32(i), "F\(i + 1)", "F\(i + 1)", fCodes[i], .function) }

        k(0x46, "Print Screen", "PrtSc", 0x69, .editing)   // macOS sees it as F13
        k(0x47, "Scroll Lock", "ScrLk", 0x6B, .editing)    // F14
        k(0x48, "Pause / Break", "Pause", 0x71, .editing)  // F15
        k(0x49, "Insert", "Ins", 0x72, .navigation)        // Help
        k(0x4A, "Home", "Home", 0x73, .navigation)
        k(0x4B, "Page Up", "PgUp", 0x74, .navigation)
        k(0x4C, "Delete", "Del", 0x75, .navigation)
        k(0x4D, "End", "End", 0x77, .navigation)
        k(0x4E, "Page Down", "PgDn", 0x79, .navigation)
        k(0x4F, "Стрелка вправо", "→", 0x7C, .navigation)
        k(0x50, "Стрелка влево", "←", 0x7B, .navigation)
        k(0x51, "Стрелка вниз", "↓", 0x7D, .navigation)
        k(0x52, "Стрелка вверх", "↑", 0x7E, .navigation)

        k(0x53, "Num Lock", "Num", 0x47, .keypad)
        k(0x54, "Цифр. блок /", "/", 0x4B, .keypad)
        k(0x55, "Цифр. блок *", "*", 0x43, .keypad)
        k(0x56, "Цифр. блок -", "-", 0x4E, .keypad)
        k(0x57, "Цифр. блок +", "+", 0x45, .keypad)
        k(0x58, "Цифр. блок Enter", "Enter", 0x4C, .keypad)
        let kpCodes: [UInt16] = [0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
        for i in 0..<9 { k(0x59 + UInt32(i), "Цифр. блок \(i + 1)", "\(i + 1)", kpCodes[i], .keypad) }
        k(0x62, "Цифр. блок 0", "0", 0x52, .keypad)
        k(0x63, "Цифр. блок .", ".", 0x41, .keypad)
        k(0x64, "Клавиша \\ у левого Shift (ISO)", "§", 0x0A, .symbols)
        k(0x65, "Menu (контекстное меню)", "Menu", 0x6E, .editing)
        k(0x66, "Power", "Power", nil, .media)
        k(0x67, "Цифр. блок =", "=", 0x51, .keypad)

        let fHighCodes: [UInt16?] = [0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A, nil, nil, nil, nil]
        for i in 0..<12 { k(0x68 + UInt32(i), "F\(i + 13)", "F\(i + 13)", fHighCodes[i], .function) }

        k(0x7F, "Mute (клавиатура)", "Mute", 0x4A, .media)
        k(0x80, "Громкость + (клавиатура)", "Vol+", 0x48, .media)
        k(0x81, "Громкость − (клавиатура)", "Vol−", 0x49, .media)

        k(0xE0, "Левый Ctrl", "Ctrl", 0x3B, .modifiers)
        k(0xE1, "Левый Shift", "Shift", 0x38, .modifiers)
        k(0xE2, "Левый Alt (⌥ Option)", "Alt", 0x3A, .modifiers)
        k(0xE3, "Левый Win (⌘ Command)", "Win", 0x37, .modifiers)
        k(0xE4, "Правый Ctrl", "Ctrl", 0x3E, .modifiers)
        k(0xE5, "Правый Shift", "Shift", 0x3C, .modifiers)
        k(0xE6, "Правый Alt (⌥ Option)", "Alt", 0x3D, .modifiers)
        k(0xE7, "Правый Win (⌘ Command)", "Win", 0x36, .modifiers)

        // Consumer page: media keys on many Windows keyboards, and useful remap targets.
        k(0xCD, "Воспроизведение / пауза", "⏯", nil, .media, page: HIDPage.consumer)
        k(0xB5, "Следующий трек", "⏭", nil, .media, page: HIDPage.consumer)
        k(0xB6, "Предыдущий трек", "⏮", nil, .media, page: HIDPage.consumer)
        k(0xE2, "Выключить звук", "🔇", nil, .media, page: HIDPage.consumer)
        k(0xE9, "Громче", "🔊", nil, .media, page: HIDPage.consumer)
        k(0xEA, "Тише", "🔉", nil, .media, page: HIDPage.consumer)
        k(0x6F, "Яркость +", "☀︎+", nil, .media, page: HIDPage.consumer)
        k(0x70, "Яркость −", "☀︎−", nil, .media, page: HIDPage.consumer)
        k(0xB8, "Извлечь", "⏏", nil, .media, page: HIDPage.consumer)
        k(0x223, "Браузер: домой", "Home", nil, .media, page: HIDPage.consumer)
        k(0x221, "Поиск", "🔍", nil, .media, page: HIDPage.consumer)
        k(0x18A, "Почта", "✉︎", nil, .media, page: HIDPage.consumer)
        k(0x192, "Калькулятор", "Calc", nil, .media, page: HIDPage.consumer)

        // Apple vendor page: the Fn / Globe key.
        k(0x03, "Fn (🌐 Globe)", "Fn", 0x3F, .modifiers, page: HIDPage.appleVendorTopCase)
        return keys
    }
}
