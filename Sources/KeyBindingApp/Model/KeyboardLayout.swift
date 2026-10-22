import CoreGraphics

/// A key cap on the drawn keyboard. Position and size are in key units (1 = one letter key).
struct KeyCap: Identifiable {
    let usage: UInt32
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var id: UInt32 { usage }
    var hid: HIDUsage { HIDUsage(page: HIDPage.keyboard, usage: usage) }
}

/// A full-size Windows keyboard (ANSI) with navigation block and numpad.
enum KeyboardLayout {
    static let width: CGFloat = 22.5
    static let height: CGFloat = 6.5

    static let keys: [KeyCap] = {
        var caps: [KeyCap] = []

        /// Lays out a row left to right. A usage of 0 is an empty gap of the given width.
        func row(_ y: CGFloat, from x: CGFloat, _ items: [(UInt32, CGFloat)]) {
            var cursor = x
            for (usage, w) in items {
                if usage != 0 { caps.append(KeyCap(usage: usage, x: cursor, y: y, width: w, height: 1)) }
                cursor += w
            }
        }
        func keys(_ range: ClosedRange<UInt32>) -> [(UInt32, CGFloat)] { range.map { ($0, 1) } }

        // Function row
        var functionRow: [(UInt32, CGFloat)] = [(0x29, 1), (0, 1)]
        functionRow += keys(0x3A...0x3D)
        functionRow.append((0, 0.5))
        functionRow += keys(0x3E...0x41)
        functionRow.append((0, 0.5))
        functionRow += keys(0x42...0x45)
        row(0, from: 0, functionRow)
        row(0, from: 15.25, [(0x46, 1), (0x47, 1), (0x48, 1)])

        // Main block
        var digitRow: [(UInt32, CGFloat)] = [(0x35, 1)]
        digitRow += keys(0x1E...0x27)
        digitRow += [(0x2D, 1), (0x2E, 1), (0x2A, 2)]
        row(1.5, from: 0, digitRow)
        row(2.5, from: 0, [(0x2B, 1.5), (0x14, 1), (0x1A, 1), (0x08, 1), (0x15, 1), (0x17, 1), (0x1C, 1), (0x18, 1),
                           (0x0C, 1), (0x12, 1), (0x13, 1), (0x2F, 1), (0x30, 1), (0x31, 1.5)])
        row(3.5, from: 0, [(0x39, 1.75), (0x04, 1), (0x16, 1), (0x07, 1), (0x09, 1), (0x0A, 1), (0x0B, 1), (0x0D, 1),
                           (0x0E, 1), (0x0F, 1), (0x33, 1), (0x34, 1), (0x28, 2.25)])
        row(4.5, from: 0, [(0xE1, 2.25), (0x1D, 1), (0x1B, 1), (0x06, 1), (0x19, 1), (0x05, 1), (0x11, 1), (0x10, 1),
                           (0x36, 1), (0x37, 1), (0x38, 1), (0xE5, 2.75)])
        row(5.5, from: 0, [(0xE0, 1.25), (0xE3, 1.25), (0xE2, 1.25), (0x2C, 6.25), (0xE6, 1.25), (0xE7, 1.25),
                           (0x65, 1.25), (0xE4, 1.25)])

        // Navigation block
        row(1.5, from: 15.25, [(0x49, 1), (0x4A, 1), (0x4B, 1)])
        row(2.5, from: 15.25, [(0x4C, 1), (0x4D, 1), (0x4E, 1)])
        row(4.5, from: 16.25, [(0x52, 1)])
        row(5.5, from: 15.25, [(0x50, 1), (0x51, 1), (0x4F, 1)])

        // Numpad
        row(1.5, from: 18.5, [(0x53, 1), (0x54, 1), (0x55, 1), (0x56, 1)])
        row(2.5, from: 18.5, [(0x5F, 1), (0x60, 1), (0x61, 1)])
        caps.append(KeyCap(usage: 0x57, x: 21.5, y: 2.5, width: 1, height: 2))
        row(3.5, from: 18.5, [(0x5C, 1), (0x5D, 1), (0x5E, 1)])
        row(4.5, from: 18.5, [(0x59, 1), (0x5A, 1), (0x5B, 1)])
        caps.append(KeyCap(usage: 0x58, x: 21.5, y: 4.5, width: 1, height: 2))
        row(5.5, from: 18.5, [(0x62, 2), (0x63, 1)])

        return caps
    }()
}
