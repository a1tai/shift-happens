import AppKit
import CoreGraphics
import Foundation

/// A HID usage (page + usage), the identity of a physical key as the keyboard reports it.
struct HIDUsage: Codable, Hashable {
    var page: UInt32
    var usage: UInt32

    /// The value `hidutil` expects in UserKeyMapping, e.g. 0x700000039 for Caps Lock.
    var hidutilValue: UInt64 { (UInt64(page) << 32) | UInt64(usage) }

    var hexDescription: String { String(format: "0x%X", hidutilValue) }
}

/// A specific keyboard, identified the way `hidutil --matching` identifies it.
struct DeviceRef: Codable, Hashable, Identifiable {
    var vendorID: Int
    var productID: Int
    var name: String
    /// The MacBook's own keyboard. It reports vendor and product 0, like other built-in HID parts
    /// (the headphone jack's buttons), so it is identified by this flag instead.
    var isBuiltIn = false
    /// A mouse whose extra buttons send key presses through a keyboard interface (e.g. Logitech M720).
    var isMouse = false

    init(vendorID: Int, productID: Int, name: String, isBuiltIn: Bool = false, isMouse: Bool = false) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isMouse = isMouse
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try c.decode(Int.self, forKey: .vendorID)
        productID = try c.decode(Int.self, forKey: .productID)
        name = try c.decode(String.self, forKey: .name)
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        isMouse = try c.decodeIfPresent(Bool.self, forKey: .isMouse) ?? false
    }

    var id: String { isBuiltIn ? "built-in" : "\(vendorID):\(productID)" }

    /// Built-in keyboard, then other keyboards, then mice.
    var sortGroup: Int { isBuiltIn ? 0 : isMouse ? 2 : 1 }

    func matches(_ other: DeviceRef) -> Bool {
        isBuiltIn || other.isBuiltIn
            ? isBuiltIn == other.isBuiltIn
            : vendorID == other.vendorID && productID == other.productID
    }
}

/// Simple key-to-key remap applied by the system (hidutil UserKeyMapping).
struct KeyRemap: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: HIDUsage
    var to: HIDUsage
    /// nil means every keyboard, including the MacBook's built-in one.
    var device: DeviceRef?
    var enabled = true

    /// Saved before fn was left out of remaps.
    var usesFn: Bool { from == KeyCatalog.fn || to == KeyCatalog.fn }
}

struct ModifierSet: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let control = ModifierSet(rawValue: 1 << 0)
    static let option = ModifierSet(rawValue: 1 << 1)
    static let shift = ModifierSet(rawValue: 1 << 2)
    static let command = ModifierSet(rawValue: 1 << 3)
    static let function = ModifierSet(rawValue: 1 << 4)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(cgFlags: CGEventFlags) {
        var set: ModifierSet = []
        if cgFlags.contains(.maskControl) { set.insert(.control) }
        if cgFlags.contains(.maskAlternate) { set.insert(.option) }
        if cgFlags.contains(.maskShift) { set.insert(.shift) }
        if cgFlags.contains(.maskCommand) { set.insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { set.insert(.function) }
        self = set
    }

    init(nsFlags: NSEvent.ModifierFlags) {
        var set: ModifierSet = []
        if nsFlags.contains(.control) { set.insert(.control) }
        if nsFlags.contains(.option) { set.insert(.option) }
        if nsFlags.contains(.shift) { set.insert(.shift) }
        if nsFlags.contains(.command) { set.insert(.command) }
        if nsFlags.contains(.function) { set.insert(.function) }
        self = set
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    /// Symbols in the standard macOS order: ⌃⌥⇧⌘.
    var symbols: String {
        var s = ""
        if contains(.function) { s += "fn " }
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A key (macOS virtual key code) plus modifiers, or a mouse button plus modifiers (combo triggers).
struct KeyChord: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: ModifierSet
    /// Set for a mouse button trigger: the CGEvent button number (2 middle, 3 back, 4 forward, …).
    /// Left and right (0 and 1) are never used. Missing in older configs.
    var mouseButton: Int? = nil

    init(keyCode: UInt16, modifiers: ModifierSet, mouseButton: Int? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.mouseButton = mouseButton
    }

    /// A real macOS key code (0…127) or an extra mouse button (2…31), and known modifier bits only.
    var isValid: Bool {
        if let mouseButton { return (2...31).contains(mouseButton) && modifiers.rawValue & ~0x1F == 0 }
        return keyCode <= 0x7F && modifiers.rawValue & ~0x1F == 0
    }

    static func mouse(_ button: Int, modifiers: ModifierSet = []) -> KeyChord {
        KeyChord(keyCode: 0, modifiers: modifiers, mouseButton: button)
    }

    /// "Middle button", "Mouse 4 (Back)", "Mouse 5 (Forward)", "Mouse 6".
    static func mouseName(_ button: Int) -> String {
        switch button {
        case 2: return "Middle button"
        case 3: return "Mouse 4 (Back)"
        case 4: return "Mouse 5 (Forward)"
        default: return "Mouse \(button + 1)"
        }
    }

    var display: String {
        if let mouseButton { return modifiers.symbols + KeyChord.mouseName(mouseButton) }
        return modifiers.symbols + (KeyChord.modifierSymbols[keyCode] ?? KeyCatalog.name(forMacKeyCode: keyCode))
    }

    /// Modifier keys as keys (macro steps), shown the Mac way; left and right look the same.
    static let modifierSymbols: [UInt16: String] = [
        0x37: "⌘", 0x36: "⌘", 0x38: "⇧", 0x3C: "⇧", 0x3A: "⌥", 0x3D: "⌥", 0x3B: "⌃", 0x3E: "⌃", 0x3F: "fn",
    ]

    /// The key on its own, with left and right modifiers told apart ("Left ⌘ Command", "C").
    var keyName: String {
        let modifierNames: [UInt16: String] = [
            0x37: "Left ⌘ Command", 0x36: "Right ⌘ Command", 0x38: "Left ⇧ Shift", 0x3C: "Right ⇧ Shift",
            0x3A: "Left ⌥ Option", 0x3D: "Right ⌥ Option", 0x3B: "Left ⌃ Control", 0x3E: "Right ⌃ Control", 0x3F: "fn",
        ]
        return modifierNames[keyCode] ?? KeyCatalog.name(forMacKeyCode: keyCode)
    }
}

/// A shortcut handled by the app's event tap: when `trigger` is pressed, `output` is sent instead,
/// or the macro is played when it has steps.
struct ComboBinding: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: KeyChord
    var output: KeyChord
    var note: String = ""
    var enabled = true
    /// Played instead of `output` when not empty.
    var macro: [MacroItem] = []
    /// Pause added between macro steps, in milliseconds.
    var stepDelay = 0
    /// Holding the trigger plays the macro again and again; otherwise it plays once per press.
    var repeatsWhileHeld = false
    /// Opened (or brought to the front) instead of sending anything, when set.
    var app: AppTarget?
    /// A built-in action (paste as plain text, run a shortcut) instead of sending anything, when set.
    var action: BuiltInAction?

    /// What the combo does: an app comes first, then a built-in action, then a macro, then the output shortcut.
    var isApp: Bool { app != nil }
    var isAction: Bool { app == nil && action != nil }
    var isMacro: Bool { app == nil && action == nil && !macro.isEmpty }

    /// Saved before fn was left out: a trigger, output or macro step that is the fn key. Such a combo can't work.
    var usesFn: Bool {
        let fn = KeyCatalog.fnKeyCode
        let keys = [trigger, output] + macro.compactMap { item -> KeyChord? in
            switch item.step {
            case .press(let c), .keyDown(let c), .keyUp(let c): return c
            default: return nil
            }
        }
        return keys.contains { $0.mouseButton == nil && $0.keyCode == fn }
    }
    var outputSummary: String {
        if let app { return app.name }
        if let action { return action.display }
        return isMacro ? macro.summary : output.display
    }

    init(trigger: KeyChord, output: KeyChord, note: String = "", enabled: Bool = true) {
        self.trigger = trigger
        self.output = output
        self.note = note
        self.enabled = enabled
    }

    // Combos saved before macros existed have no macro fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try c.decode(KeyChord.self, forKey: .trigger)
        output = try c.decode(KeyChord.self, forKey: .output)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // Press steps from an earlier version become the key events they stand for.
        macro = (try c.decodeIfPresent([MacroItem].self, forKey: .macro) ?? []).flatMap { item -> [MacroItem] in
            guard case .press(let chord) = item.step else { return [item] }
            return MacroStep.events(for: chord).map { MacroItem(step: $0) }
        }
        stepDelay = try c.decodeIfPresent(Int.self, forKey: .stepDelay) ?? 0
        repeatsWhileHeld = try c.decodeIfPresent(Bool.self, forKey: .repeatsWhileHeld) ?? false
        app = try c.decodeIfPresent(AppTarget.self, forKey: .app)
        // An action this version doesn't know (from a newer one) leaves the combo without it.
        action = try? c.decodeIfPresent(BuiltInAction.self, forKey: .action)
    }
}

/// The key whose lone press fixes the layout of the last word or selection.
enum LayoutTrigger: String, Codable, CaseIterable, Identifiable {
    case bothOptions, leftOption, rightOption, fn, capsLock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bothOptions: return "Either Option ⌥"
        case .leftOption: return "Left Option ⌥"
        case .rightOption: return "Right Option ⌥"
        case .fn: return "fn 🌐"
        case .capsLock: return "Caps Lock ⇪"
        }
    }
}

struct LayoutFixerSettings: Codable, Equatable {
    var enabled = false
    var trigger: LayoutTrigger = .bothOptions
    var switchesWhenNothingToFix = false
    var switchesAfterFixing = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        trigger = (try? c.decodeIfPresent(LayoutTrigger.self, forKey: .trigger)) ?? .bothOptions
        switchesWhenNothingToFix = try c.decodeIfPresent(Bool.self, forKey: .switchesWhenNothingToFix) ?? false
        switchesAfterFixing = try c.decodeIfPresent(Bool.self, forKey: .switchesAfterFixing) ?? true
    }
}

/// Everything the app saves to disk.
struct AppConfig: Codable, Equatable {
    /// Limits for anything read from disk or imported, so a broken or hostile file can't hang the app
    /// or make it type for minutes.
    enum Limits {
        static let bindings = 500
        static let macroSteps = 1_000
        static let delay = 60_000        // ms per delay step
        static let stepDelay = 5_000     // ms between steps
        static let textLength = 1_000    // characters per Type text step
        static let noteLength = 200
    }

    /// The config with every list, delay and text cut to the limits, and impossible keys dropped.
    func sanitized() -> AppConfig {
        var config = self
        config.remaps = Array(remaps.filter { $0.from.page <= 0xFF && $0.to.page <= 0xFF }.prefix(Limits.bindings))
        config.knownDevices = Array(knownDevices.prefix(Limits.bindings))
        config.combos = Array(combos.prefix(Limits.bindings)).compactMap { combo in
            var combo = combo
            guard combo.trigger.isValid, combo.output.isValid else { return nil }
            if let app = combo.app {
                guard let safe = app.sanitized() else { return nil }
                combo.app = safe
            }
            if let action = combo.action {
                guard let safe = action.sanitized() else { return nil }
                combo.action = safe
            }
            combo.note = String(combo.note.prefix(Limits.noteLength))
            combo.stepDelay = min(max(combo.stepDelay, 0), Limits.stepDelay)
            combo.macro = Array(combo.macro.prefix(Limits.macroSteps)).compactMap { item in
                var item = item
                switch item.step {
                case .press(let key), .keyDown(let key), .keyUp(let key):
                    guard key.isValid else { return nil }
                case .delay(let ms):
                    item.step = .delay(min(max(ms, 0), Limits.delay))
                case .text(let text):
                    item.step = .text(String(text.prefix(Limits.textLength)))
                case .openApp(let app):
                    guard let safe = app.sanitized() else { return nil }
                    item.step = .openApp(safe)
                }
                return item
            }
            return combo
        }
        return config
    }

    var remaps: [KeyRemap] = []
    var combos: [ComboBinding] = []
    /// Master switch from the menu bar.
    var enabled = true
    /// Devices we have applied per-device mappings to, so they can be cleared later.
    var knownDevices: [DeviceRef] = []
    var layoutFixer = LayoutFixerSettings()
    /// The current input language ("EN", "RU") next to the app's menu bar icon, so the system's own
    /// input menu can be turned off.
    var showsInputLanguage = true

    init() {}

    // Every field is optional so config files from older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remaps = try c.decodeIfPresent([KeyRemap].self, forKey: .remaps) ?? []
        combos = try c.decodeIfPresent([ComboBinding].self, forKey: .combos) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        knownDevices = try c.decodeIfPresent([DeviceRef].self, forKey: .knownDevices) ?? []
        layoutFixer = try c.decodeIfPresent(LayoutFixerSettings.self, forKey: .layoutFixer) ?? LayoutFixerSettings()
        showsInputLanguage = try c.decodeIfPresent(Bool.self, forKey: .showsInputLanguage) ?? true
    }
}
