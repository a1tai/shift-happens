import CoreGraphics

/// A key cap on the drawn keyboard. Position and size are in key units (1 = one letter key).
struct KeyCap: Identifiable {
    var page: UInt32 = HIDPage.keyboard
    let usage: UInt32
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// The text printed on this keyboard's cap, when it differs from the catalog's label.
    /// A line break puts a glyph above a word, as on Mac modifier keys ("⌘\ncommand").
    var label: String?

    var hid: HIDUsage { HIDUsage(page: page, usage: usage) }
    var id: UInt64 { hid.hidutilValue }
}

/// A drawn keyboard. The same HID usages sit under both drawings (left ⌘ and left Win are both 0xE3),
/// so remaps, combos and pressed keys show up on either one.
struct KeyboardLayout {
    let width: CGFloat
    let height: CGFloat
    let keys: [KeyCap]

    enum Style: String, CaseIterable, Identifiable {
        case mac, windows

        var id: String { rawValue }
        var title: String { self == .mac ? "Mac" : "Windows" }
        var layout: KeyboardLayout { self == .mac ? .mac : .windows }
    }

    /// Mac-style name for a key, used for remap targets on the Mac drawing.
    static func macLabel(for usage: HIDUsage) -> String? {
        guard usage.page == HIDPage.keyboard else { return usage.page == HIDPage.appleVendorTopCase && usage.usage == 0x03 ? "fn" : nil }
        switch usage.usage {
        case 0x28: return "return"
        case 0x29: return "esc"
        case 0x2A: return "delete"
        case 0x2B: return "tab"
        case 0x39: return "caps lock"
        case 0xE0, 0xE4: return "⌃"
        case 0xE1, 0xE5: return "⇧"
        case 0xE2, 0xE6: return "⌥"
        case 0xE3, 0xE7: return "⌘"
        default: return nil
        }
    }

    /// Lays out a row left to right. A usage of 0 is an empty gap of the given width.
    private static func row(_ y: CGFloat, from x: CGFloat, _ items: [(UInt32, CGFloat)], into caps: inout [KeyCap]) {
        var cursor = x
        for (usage, w) in items {
            if usage != 0 { caps.append(KeyCap(usage: usage, x: cursor, y: y, width: w, height: 1)) }
            cursor += w
        }
    }

    private static func keys(_ range: ClosedRange<UInt32>) -> [(UInt32, CGFloat)] { range.map { ($0, 1) } }

    /// A full-size Windows keyboard (ANSI) with navigation block and numpad.
    static let windows: KeyboardLayout = {
        var caps: [KeyCap] = []

        // Function row
        var functionRow: [(UInt32, CGFloat)] = [(0x29, 1), (0, 1)]
        functionRow += keys(0x3A...0x3D)
        functionRow.append((0, 0.5))
        functionRow += keys(0x3E...0x41)
        functionRow.append((0, 0.5))
        functionRow += keys(0x42...0x45)
        row(0, from: 0, functionRow, into: &caps)
        row(0, from: 15.25, [(0x46, 1), (0x47, 1), (0x48, 1)], into: &caps)

        // Main block
        var digitRow: [(UInt32, CGFloat)] = [(0x35, 1)]
        digitRow += keys(0x1E...0x27)
        digitRow += [(0x2D, 1), (0x2E, 1), (0x2A, 2)]
        row(1.5, from: 0, digitRow, into: &caps)
        row(2.5, from: 0, [(0x2B, 1.5), (0x14, 1), (0x1A, 1), (0x08, 1), (0x15, 1), (0x17, 1), (0x1C, 1), (0x18, 1),
                           (0x0C, 1), (0x12, 1), (0x13, 1), (0x2F, 1), (0x30, 1), (0x31, 1.5)], into: &caps)
        row(3.5, from: 0, [(0x39, 1.75), (0x04, 1), (0x16, 1), (0x07, 1), (0x09, 1), (0x0A, 1), (0x0B, 1), (0x0D, 1),
                           (0x0E, 1), (0x0F, 1), (0x33, 1), (0x34, 1), (0x28, 2.25)], into: &caps)
        row(4.5, from: 0, [(0xE1, 2.25), (0x1D, 1), (0x1B, 1), (0x06, 1), (0x19, 1), (0x05, 1), (0x11, 1), (0x10, 1),
                           (0x36, 1), (0x37, 1), (0x38, 1), (0xE5, 2.75)], into: &caps)
        row(5.5, from: 0, [(0xE0, 1.25), (0xE3, 1.25), (0xE2, 1.25), (0x2C, 6.25), (0xE6, 1.25), (0xE7, 1.25),
                           (0x65, 1.25), (0xE4, 1.25)], into: &caps)

        // Navigation block
        row(1.5, from: 15.25, [(0x49, 1), (0x4A, 1), (0x4B, 1)], into: &caps)
        row(2.5, from: 15.25, [(0x4C, 1), (0x4D, 1), (0x4E, 1)], into: &caps)
        row(4.5, from: 16.25, [(0x52, 1)], into: &caps)
        row(5.5, from: 15.25, [(0x50, 1), (0x51, 1), (0x4F, 1)], into: &caps)

        // Numpad
        row(1.5, from: 18.5, [(0x53, 1), (0x54, 1), (0x55, 1), (0x56, 1)], into: &caps)
        row(2.5, from: 18.5, [(0x5F, 1), (0x60, 1), (0x61, 1)], into: &caps)
        caps.append(KeyCap(usage: 0x57, x: 21.5, y: 2.5, width: 1, height: 2))
        row(3.5, from: 18.5, [(0x5C, 1), (0x5D, 1), (0x5E, 1)], into: &caps)
        row(4.5, from: 18.5, [(0x59, 1), (0x5A, 1), (0x5B, 1)], into: &caps)
        caps.append(KeyCap(usage: 0x58, x: 21.5, y: 4.5, width: 1, height: 2))
        row(5.5, from: 18.5, [(0x62, 2), (0x63, 1)], into: &caps)

        return KeyboardLayout(width: 22.5, height: 6.5, keys: caps)
    }()

    /// A MacBook's built-in keyboard (ANSI, US), with the inverted-T arrow keys.
    static let mac: KeyboardLayout = {
        var caps: [KeyCap] = []
        func key(_ usage: UInt32, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, h: CGFloat = 1,
                 page: UInt32 = HIDPage.keyboard, _ label: String? = nil) {
            caps.append(KeyCap(page: page, usage: usage, x: x, y: y, width: w, height: h, label: label))
        }

        // Function row: esc, F1–F12, and the Touch ID button (not a key) left blank.
        key(0x29, 0, 0, 1.5, "esc")
        for i in 0..<12 { key(0x3A + UInt32(i), 1.5 + CGFloat(i), 0, 1) }

        // Number row
        var x: CGFloat = 0
        for usage in [0x35, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E] as [UInt32] {
            key(usage, x, 1, 1)
            x += 1
        }
        key(0x2A, x, 1, 1.5, "delete")

        // Letter rows
        key(0x2B, 0, 2, 1.5, "tab")
        x = 1.5
        for usage in [0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13, 0x2F, 0x30, 0x31] as [UInt32] {
            key(usage, x, 2, 1)
            x += 1
        }
        key(0x39, 0, 3, 1.75, "⇪\ncaps lock")
        x = 1.75
        for usage in [0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33, 0x34] as [UInt32] {
            key(usage, x, 3, 1)
            x += 1
        }
        key(0x28, x, 3, 1.75, "return")
        key(0xE1, 0, 4, 2.25, "⇧\nshift")
        x = 2.25
        for usage in [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10, 0x36, 0x37, 0x38] as [UInt32] {
            key(usage, x, 4, 1)
            x += 1
        }
        key(0xE5, x, 4, 2.25, "⇧\nshift")

        // Bottom row: fn, control, option, command, space, command, option, arrows.
        key(0x03, 0, 5, 1, page: HIDPage.appleVendorTopCase, "fn\n🌐")
        key(0xE0, 1, 5, 1, "⌃\ncontrol")
        key(0xE2, 2, 5, 1, "⌥\noption")
        key(0xE3, 3, 5, 1.25, "⌘\ncommand")
        key(0x2C, 4.25, 5, 5, " ")
        key(0xE7, 9.25, 5, 1.25, "⌘\ncommand")
        key(0xE6, 10.5, 5, 1, "⌥\noption")
        key(0x50, 11.5, 5.5, 1, h: 0.5)
        key(0x52, 12.5, 5, 1, h: 0.5)
        key(0x51, 12.5, 5.5, 1, h: 0.5)
        key(0x4F, 13.5, 5.5, 1, h: 0.5)

        return KeyboardLayout(width: 14.5, height: 6, keys: caps)
    }()
}
