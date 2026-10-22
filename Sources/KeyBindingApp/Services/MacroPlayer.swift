import CoreGraphics
import Foundation

/// Where a macro's key events go. The real one posts CGEvents; the self-test records them.
protocol KeyEventPosting {
    func key(_ keyCode: UInt16, down: Bool, modifiers: ModifierSet)
    func text(_ text: String)
    func wait(milliseconds: Int)
}

/// Posts key events at the HID level, marked so the app's own event taps let them through.
struct CGEventPoster: KeyEventPosting {
    private let source: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = SyntheticEvent.combo
        return source
    }()

    func key(_ keyCode: UInt16, down: Bool, modifiers: ModifierSet) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = modifiers.cgFlags
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.combo)
        event.post(tap: .cghidEventTap)
    }

    func text(_ text: String) {
        // Unicode text goes in chunks; one event carries at most about 20 characters.
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 20) {
            var chunk = Array(units[start..<min(start + 20, units.count)])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.combo)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    func wait(milliseconds: Int) {
        usleep(useconds_t(max(0, milliseconds)) * 1000)
    }
}

/// Plays macros on a background queue, one at a time per combo, so the event tap is never held up.
final class MacroPlayer {
    private let queue = DispatchQueue(label: "ShiftHappens.macros")
    private let lock = NSLock()
    private var running = Set<UUID>()
    private var generation = 0
    var poster: KeyEventPosting = CGEventPoster()

    func isRunning(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running.contains(id)
    }

    /// Starts the combo's macro unless it is already running.
    func play(_ combo: ComboBinding) {
        lock.lock()
        guard !running.contains(combo.id) else { lock.unlock(); return }
        running.insert(combo.id)
        let started = generation
        lock.unlock()

        let poster = self.poster
        queue.async { [weak self] in
            Self.run(combo.macro.map(\.step), stepDelay: combo.stepDelay, poster: poster) {
                guard let self else { return true }
                self.lock.lock(); defer { self.lock.unlock() }
                return self.generation != started
            }
            self?.lock.lock()
            self?.running.remove(combo.id)
            self?.lock.unlock()
        }
    }

    /// Stops every running macro at its next step (keys it holds are still released).
    func cancelAll() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    /// Plays steps in order. Whatever happens, every key the macro pressed is released at the end,
    /// so nothing stays stuck down.
    static func run(_ steps: [MacroStep], stepDelay: Int, poster: KeyEventPosting, isCancelled: () -> Bool) {
        var held: [UInt16: ModifierSet] = [:]
        defer {
            for (keyCode, modifiers) in held { poster.key(keyCode, down: false, modifiers: modifiers) }
        }
        for (index, step) in steps.enumerated() {
            if isCancelled() { return }
            switch step {
            case .press(let chord):
                poster.key(chord.keyCode, down: true, modifiers: chord.modifiers)
                poster.key(chord.keyCode, down: false, modifiers: chord.modifiers)
            case .keyDown(let chord):
                poster.key(chord.keyCode, down: true, modifiers: chord.modifiers)
                held[chord.keyCode] = chord.modifiers
            case .keyUp(let chord):
                poster.key(chord.keyCode, down: false, modifiers: held[chord.keyCode] ?? chord.modifiers)
                held[chord.keyCode] = nil
            case .delay(let ms):
                poster.wait(milliseconds: ms)
            case .text(let text):
                poster.text(text)
            }
            let next = steps.dropFirst(index + 1).first
            if stepDelay > 0, !step.isDelay, let next, !next.isDelay {
                poster.wait(milliseconds: stepDelay)
            }
        }
    }
}
