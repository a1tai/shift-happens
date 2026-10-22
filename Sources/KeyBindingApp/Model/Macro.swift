import Foundation

/// One step of a macro that a combo plays instead of a single shortcut. A macro says exactly what the
/// keyboard does: ⌘C is ⌘ down, C down, C up, ⌘ up. Modifier keys are keys like any other.
enum MacroStep: Codable, Hashable {
    /// Press and release in one step. Only in macros saved by an earlier version; still played.
    case press(KeyChord)
    /// A key goes down (and stays down until its keyUp, or the end of the macro).
    case keyDown(KeyChord)
    case keyUp(KeyChord)
    /// Wait, in milliseconds.
    case delay(Int)
    /// Type text as it is, independent of the keyboard layout.
    case text(String)
    /// Open or bring an app to the front, and wait until it is in front.
    case openApp(AppTarget)

    var display: String {
        switch self {
        case .press(let chord): return chord.display
        case .keyDown(let chord): return chord.display + "↓"
        case .keyUp(let chord): return chord.display + "↑"
        case .delay(let ms): return "\(ms) ms"
        case .text(let text): return "“\(text)”"
        case .openApp(let app): return "Open \(app.name)"
        }
    }

    /// The key events a shortcut is made of: modifiers down, key down, key up, modifiers up.
    static func events(for chord: KeyChord) -> [MacroStep] {
        let modifierKeys: [(ModifierSet, UInt16)] = [(.control, 0x3B), (.option, 0x3A), (.shift, 0x38), (.command, 0x37)]
        let mods = modifierKeys.filter { chord.modifiers.contains($0.0) }.map { KeyChord(keyCode: $0.1, modifiers: []) }
        let key = KeyChord(keyCode: chord.keyCode, modifiers: [])
        return mods.map(MacroStep.keyDown) + [.keyDown(key), .keyUp(key)] + mods.reversed().map(MacroStep.keyUp)
    }

    var isDelay: Bool {
        if case .delay = self { return true }
        return false
    }
}

/// A macro step with an identity, so the editor's list can move and edit rows.
struct MacroItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var step: MacroStep
}

extension Array where Element == MacroItem {
    /// "⌘C · 100 ms · ⌘V"
    var summary: String { map(\.step.display).joined(separator: " · ") }

    /// Explicit delays plus the pause between steps.
    func duration(stepDelay: Int) -> Int {
        let delays = reduce(0) { total, item in
            if case .delay(let ms) = item.step { return total + ms }
            return total
        }
        let gaps = Swift.max(0, filter { !$0.step.isDelay }.count - 1)
        return delays + gaps * stepDelay
    }
}

/// Turns raw key presses into macro steps while the user records a macro: every key going down or up,
/// modifiers included, in order; optionally with the time between them as delay steps.
struct MacroRecorder {
    var recordsDelays: Bool
    private(set) var steps: [MacroStep] = []
    private var lastEvent: Date?
    /// Keys down right now: a second "down" for one of them is a duplicate report, not a new press.
    private var heldKeys: Set<UInt16> = []

    init(recordsDelays: Bool) { self.recordsDelays = recordsDelays }

    /// Delays shorter than this are typing noise, not pauses.
    static let minimumDelay = 10

    mutating func handle(_ usage: HIDUsage, isDown: Bool, at time: Date) {
        guard usage.page == HIDPage.keyboard, let code = KeyCatalog.key(for: usage)?.macKeyCode else { return }
        if isDown {
            guard heldKeys.insert(code).inserted else { return }
        } else {
            guard heldKeys.remove(code) != nil else { return }
        }
        if recordsDelays, !steps.isEmpty, let lastEvent {
            let ms = Int((time.timeIntervalSince(lastEvent) * 1000 / 10).rounded()) * 10
            if ms >= Self.minimumDelay { steps.append(.delay(ms)) }
        }
        let key = KeyChord(keyCode: code, modifiers: [])
        steps.append(isDown ? .keyDown(key) : .keyUp(key))
        lastEvent = time
    }
}

extension Array where Element == MacroItem {
    /// Cleans up a recording: drops delays shorter than `minimumDelay` ms and merges delays that follow
    /// each other. Key events are left as they are.
    func withoutShortDelays(below minimumDelay: Int) -> [MacroItem] {
        var result: [MacroItem] = []
        for item in self {
            guard case .delay(let ms) = item.step else { result.append(item); continue }
            if ms < minimumDelay { continue }
            if case .delay(let previous)? = result.last?.step {
                result[result.count - 1].step = .delay(previous + ms)
            } else {
                result.append(item)
            }
        }
        return result
    }

    /// Keys released without being pressed first, and keys pressed and never released.
    var unmatchedKeys: (upWithoutDown: [KeyChord], neverReleased: [KeyChord]) {
        var held: [UInt16] = []
        var upWithoutDown: [KeyChord] = []
        for item in self {
            switch item.step {
            case .keyDown(let key): if !held.contains(key.keyCode) { held.append(key.keyCode) }
            case .keyUp(let key):
                if let index = held.firstIndex(of: key.keyCode) { held.remove(at: index) } else { upWithoutDown.append(key) }
            default: break
            }
        }
        return (upWithoutDown, held.map { KeyChord(keyCode: $0, modifiers: []) })
    }
}
