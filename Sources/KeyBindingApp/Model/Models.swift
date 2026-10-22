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

    var id: String { "\(vendorID):\(productID)" }

    func matches(_ other: DeviceRef) -> Bool { vendorID == other.vendorID && productID == other.productID }
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

    var display: String { modifiers.symbols + KeyCatalog.name(forMacKeyCode: keyCode) }
}

/// A shortcut handled by the app's event tap: when `trigger` is pressed, `output` is sent instead.
struct ComboBinding: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: KeyChord
    var output: KeyChord
    var note: String = ""
    var enabled = true
}

/// Everything the app saves to disk.
struct AppConfig: Codable, Equatable {
    var remaps: [KeyRemap] = []
    var combos: [ComboBinding] = []
    /// Master switch from the menu bar.
    var enabled = true
    /// Devices we have applied per-device mappings to, so they can be cleared later.
    var knownDevices: [DeviceRef] = []
}
