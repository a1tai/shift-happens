import Foundation

/// Builds a shortcut from raw HID key presses while the user records one. Raw input also sees
/// shortcuts macOS keeps to itself (⌘⇧4, ⌘Space, ⌘Tab), which never reach the app as key events.
struct ChordTracker {
    /// Modifier keys held down right now (HID usages E0–E7, after remaps).
    private(set) var heldModifiers: Set<UInt32> = []

    /// Feeds one press or release. Returns the shortcut once a non-modifier key goes down.
    mutating func handle(_ usage: HIDUsage, isDown: Bool) -> KeyChord? {
        guard usage.page == HIDPage.keyboard else { return nil }
        if Self.modifier(for: usage.usage) != nil {
            if isDown { heldModifiers.insert(usage.usage) } else { heldModifiers.remove(usage.usage) }
            return nil
        }
        guard isDown, let keyCode = KeyCatalog.key(for: usage)?.macKeyCode else { return nil }
        let modifiers = heldModifiers.compactMap(Self.modifier(for:)).reduce(into: ModifierSet()) { $0.insert($1) }
        return KeyChord(keyCode: keyCode, modifiers: modifiers)
    }

    /// Left and right Control, Shift, Option (Alt) and Command (Win).
    static func modifier(for usage: UInt32) -> ModifierSet? {
        switch usage {
        case 0xE0, 0xE4: return .control
        case 0xE1, 0xE5: return .shift
        case 0xE2, 0xE6: return .option
        case 0xE3, 0xE7: return .command
        default: return nil
        }
    }
}

/// Turns macOS's own keyboard shortcuts (screenshots, Spotlight, app switcher) off while a shortcut is
/// being recorded, so pressing ⌘⇧4 records it instead of taking a screenshot. Uses the private
/// CGSSetGlobalHotKeyOperatingMode call that shortcut recorders rely on; if it is missing, nothing happens.
enum SystemShortcuts {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetMode = @convention(c) (Int32, Int32) -> Int32
    private static let enableMode: Int32 = 0
    private static let disableMode: Int32 = 1

    private static let functions: (MainConnection, SetMode)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "CGSMainConnectionID"),
              let set = dlsym(handle, "CGSSetGlobalHotKeyOperatingMode") else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(set, to: SetMode.self))
    }()

    private(set) static var isDisabled = false
    static var isAvailable: Bool { functions != nil }

    static func disable() {
        guard !isDisabled, let (main, set) = functions else { return }
        _ = set(main(), disableMode)
        isDisabled = true
    }

    /// Always safe to call; also called when the app quits.
    static func restore() {
        guard isDisabled, let (main, set) = functions else { return }
        _ = set(main(), enableMode)
        isDisabled = false
    }
}
