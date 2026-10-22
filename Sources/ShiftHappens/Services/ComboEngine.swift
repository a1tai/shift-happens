import ApplicationServices
import CoreGraphics
import Foundation

/// Values in eventSourceUserData that mark key events the app posts itself,
/// so neither event tap reacts to the other's (or its own) output.
enum SyntheticEvent {
    static let combo: Int64 = 0x4B42_4150 // "KBAP"
    static let layoutFixer: Int64 = 0x4B42_4C46 // "KBLF"
}

/// Turns one key combination into another with a CGEventTap.
/// Needs the Accessibility permission (System Settings > Privacy & Security > Accessibility).
final class ComboEngine {

    var bindings: [ComboBinding] = []
    /// Temporarily lets every key through, e.g. while the user records a new shortcut.
    var isPaused = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var swallowedKeyUps = Set<UInt16>()
    private var swallowedMouseUps = Set<Int>()
    private let source = CGEventSource(stateID: .privateState)
    let macros = MacroPlayer()

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        // Keys, and the extra mouse buttons (never left or right clicks).
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<ComboEngine>.fromOpaque(context).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        macros.cancelAll()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        swallowedKeyUps.removeAll()
        swallowedMouseUps.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns slow taps off; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .otherMouseDown, .otherMouseUp:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        if isPaused || [SyntheticEvent.combo, SyntheticEvent.layoutFixer].contains(event.getIntegerValueField(.eventSourceUserData)) {
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown || type == .otherMouseUp {
            return handleMouse(down: type == .otherMouseDown, event: event)
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyUp {
            return swallowedKeyUps.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
        }

        let modifiers = ModifierSet(cgFlags: event.flags)
        guard let binding = Self.binding(in: bindings, keyCode: keyCode, mouseButton: nil, modifiers: modifiers) else {
            return Unmanaged.passUnretained(event)
        }

        // Swallow the trigger's key-up too, so no key or modifier ever gets stuck.
        swallowedKeyUps.insert(keyCode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let app = binding.app {
            // Once per press: holding the key must not toggle the app back and forth.
            if !isRepeat { open(app) }
        } else if binding.isMacro {
            // A held key repeats; a macro runs again only if asked to, and never twice at once.
            if !isRepeat || binding.repeatsWhileHeld { macros.play(binding) }
        } else {
            // A full press of the output on every key-down, auto-repeat included.
            post(binding.output)
        }
        return nil
    }

    /// A bound mouse button: its press fires the combo, and both press and release are swallowed.
    private func handleMouse(down: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard button >= 2 else { return Unmanaged.passUnretained(event) }
        if !down {
            return swallowedMouseUps.remove(button) != nil ? nil : Unmanaged.passUnretained(event)
        }
        guard let binding = Self.binding(in: bindings, keyCode: nil, mouseButton: button,
                                         modifiers: ModifierSet(cgFlags: event.flags)) else {
            return Unmanaged.passUnretained(event)
        }
        swallowedMouseUps.insert(button)
        if let app = binding.app { open(app) } else if binding.isMacro { macros.play(binding) } else { post(binding.output) }
        return nil
    }

    /// The enabled combo whose trigger is this key or mouse button with exactly these modifiers (fn ignored).
    static func binding(in bindings: [ComboBinding], keyCode: UInt16?, mouseButton: Int?,
                        modifiers: ModifierSet) -> ComboBinding? {
        let mods = modifiers.subtracting(.function)
        return bindings.first { combo in
            guard combo.enabled, combo.trigger.modifiers.subtracting(.function) == mods else { return false }
            if let mouseButton { return combo.trigger.mouseButton == mouseButton }
            return combo.trigger.mouseButton == nil && combo.trigger.keyCode == keyCode
        }
    }

    /// Outside the event tap's callback, so the tap never waits for the app to open.
    private func open(_ app: AppTarget) {
        DispatchQueue.main.async { AppLauncher.open(app) }
    }

    private func post(_ chord: KeyChord) {
        let flags = chord.modifiers.cgFlags
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.combo)
            // Posting at the HID level lets system shortcuts (screenshots, Mission Control) react too.
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Permission

    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings > Accessibility.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
