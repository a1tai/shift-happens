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

/// A key (macOS virtual key code) plus modifiers.
struct KeyChord: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: ModifierSet

    var display: String { modifiers.symbols + (KeyChord.modifierSymbols[keyCode] ?? KeyCatalog.name(forMacKeyCode: keyCode)) }

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

    var isMacro: Bool { !macro.isEmpty }
    var outputSummary: String { isMacro ? macro.summary : output.display }

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
    /// Shows the current layout (En / Ру) as a separate menu bar item.
    var showsLayoutInMenuBar = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        trigger = (try? c.decodeIfPresent(LayoutTrigger.self, forKey: .trigger)) ?? .bothOptions
        showsLayoutInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showsLayoutInMenuBar) ?? false
    }
}

/// Everything the app saves to disk.
struct AppConfig: Codable, Equatable {
    var remaps: [KeyRemap] = []
    var combos: [ComboBinding] = []
    /// Master switch from the menu bar.
    var enabled = true
    /// Devices we have applied per-device mappings to, so they can be cleared later.
    var knownDevices: [DeviceRef] = []
    var layoutFixer = LayoutFixerSettings()

    init() {}

    // Every field is optional so config files from older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remaps = try c.decodeIfPresent([KeyRemap].self, forKey: .remaps) ?? []
        combos = try c.decodeIfPresent([ComboBinding].self, forKey: .combos) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        knownDevices = try c.decodeIfPresent([DeviceRef].self, forKey: .knownDevices) ?? []
        layoutFixer = try c.decodeIfPresent(LayoutFixerSettings.self, forKey: .layoutFixer) ?? LayoutFixerSettings()
    }
}
