import Foundation

/// One step of a macro that a combo plays instead of a single shortcut.
enum MacroStep: Codable, Hashable {
    /// Press and release a key with modifiers.
    case press(KeyChord)
    /// Hold a key down (released by a later keyUp, or at the end of the macro).
    case keyDown(KeyChord)
    case keyUp(KeyChord)
    /// Wait, in milliseconds.
    case delay(Int)
    /// Type text as it is, independent of the keyboard layout.
    case text(String)

    var display: String {
        switch self {
        case .press(let chord): return chord.display
        case .keyDown(let chord): return chord.display + " down"
        case .keyUp(let chord): return chord.display + " up"
        case .delay(let ms): return "\(ms) ms"
        case .text(let text): return "“\(text)”"
        }
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

/// Turns raw key presses into macro steps while the user records a macro.
/// A key pressed and released with nothing in between becomes one "press" step; modifiers held at the
/// time become part of the step. Optionally the time between presses becomes delay steps.
struct MacroRecorder {
    var recordsDelays: Bool
    private(set) var steps: [MacroStep] = []
    private var heldModifiers: Set<UInt32> = []
    /// A modifier pressed with no other key yet; released alone, it is recorded as a press of its own.
    private var loneModifier: UInt32?
    private var lastEvent: Date?

    init(recordsDelays: Bool) { self.recordsDelays = recordsDelays }

    /// Delays shorter than this are typing noise, not pauses.
    static let minimumDelay = 10

    mutating func handle(_ usage: HIDUsage, isDown: Bool, at time: Date) {
        guard usage.page == HIDPage.keyboard else { return }

        if ChordTracker.modifier(for: usage.usage) != nil {
            if isDown {
                // Not the end of a pause: the pause runs until the key pressed together with it.
                heldModifiers.insert(usage.usage)
                loneModifier = usage.usage
                return
            } else {
                heldModifiers.remove(usage.usage)
                if loneModifier == usage.usage, let code = KeyCatalog.key(for: usage)?.macKeyCode {
                    append(.press(KeyChord(keyCode: code, modifiers: modifiers)), at: time)
                }
                loneModifier = nil
            }
            lastEvent = time
            return
        }

        guard let code = KeyCatalog.key(for: usage)?.macKeyCode else { return }
        defer { lastEvent = time }
        loneModifier = nil
        if isDown {
            append(.keyDown(KeyChord(keyCode: code, modifiers: modifiers)), at: time)
        } else if case .keyDown(let chord)? = steps.last, chord.keyCode == code {
            // Down and up of the same key with nothing in between: one press. The hold time is dropped.
            steps[steps.count - 1] = .press(chord)
        } else {
            append(.keyUp(KeyChord(keyCode: code, modifiers: [])), at: time)
        }
    }

    private var modifiers: ModifierSet {
        heldModifiers.compactMap(ChordTracker.modifier(for:)).reduce(into: ModifierSet()) { $0.insert($1) }
    }

    private mutating func append(_ step: MacroStep, at time: Date) {
        if recordsDelays, !steps.isEmpty, let lastEvent {
            let ms = Int((time.timeIntervalSince(lastEvent) * 1000 / 10).rounded()) * 10
            if ms >= Self.minimumDelay { steps.append(.delay(ms)) }
        }
        steps.append(step)
    }
}
