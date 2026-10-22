import Foundation

/// One physical press as the keyboard reported it, for the Key Monitor: every HID event from the first
/// key going down until all keys are up again. Special keys on many keyboards send a whole shortcut
/// (Win+Shift+S, Ctrl+Alt+X) as several usages; this keeps them together as one press.
/// Lives in memory only, and only the current or last one exists.
struct KeyGesture: Identifiable, Equatable {
    struct Event: Equatable {
        let usage: HIDUsage
        let isDown: Bool
        let device: DeviceRef
        let time: Date
    }

    /// A key event macOS delivered to the app during the press.
    struct MacKey: Equatable {
        let keyCode: UInt16
        let characters: String?
        let modifiers: ModifierSet
    }

    /// Some keyboards send the modifier and the key a moment apart, or let go of one before pressing
    /// the next: a key going down this soon after everything was released still belongs to the press.
    static let grace: TimeInterval = 0.08
    /// Holding a key while typing others is still one press; it never grows into a record of typing.
    static let maxEvents = 16
    static let maxKeys = 6

    let id = UUID()
    let start: Date
    private(set) var events: [Event] = []
    /// Distinct usages that went down, in the order they went down.
    private(set) var keys: [HIDUsage] = []
    private(set) var held: Set<HIDUsage> = []
    private(set) var releasedAt: Date?
    private(set) var macKeys: [MacKey] = []
    /// macOS reported a modifier change (⌘, ⇧…) during the press.
    private(set) var macSawModifiers = false
    /// Every modifier macOS reported as held at some point during the press.
    private(set) var macModifiers: ModifierSet = []

    init(start: Date) { self.start = start }

    /// A press seen only through macOS (no Input Monitoring access).
    init(macKey: MacKey, time: Date) {
        start = time
        macKeys = [macKey]
        macModifiers = macKey.modifiers
    }

    var isHeld: Bool { !held.isEmpty }

    /// Whether `event` continues this press rather than starting a new one.
    func continues(with event: Event) -> Bool {
        if isHeld { return true }
        guard event.isDown, let releasedAt else { return false }
        return event.time.timeIntervalSince(releasedAt) <= Self.grace
    }

    /// Feeds one HID event into the monitor's current press. Returns the press it belongs to:
    /// `current` extended, or a new one. A release of a key that isn't part of a press is ignored.
    static func adding(_ event: Event, to current: KeyGesture?) -> KeyGesture? {
        if var gesture = current, gesture.continues(with: event) {
            gesture.add(event)
            return gesture
        }
        guard event.isDown else { return current }
        var gesture = KeyGesture(start: event.time)
        gesture.add(event)
        return gesture
    }

    private mutating func add(_ event: Event) {
        if event.isDown {
            guard held.insert(event.usage).inserted else { return }
            if !keys.contains(event.usage), keys.count < Self.maxKeys { keys.append(event.usage) }
            releasedAt = nil
        } else {
            guard held.remove(event.usage) != nil else { return }
            if held.isEmpty { releasedAt = event.time }
        }
        if events.count < Self.maxEvents { events.append(event) }
    }

    /// Adds what macOS made of the press: a key down, or a modifier change.
    mutating func addMac(keyCode: UInt16, characters: String?, modifiers: ModifierSet, isModifierChange: Bool) {
        macModifiers.formUnion(modifiers.subtracting(.function))
        if isModifierChange {
            macSawModifiers = true
        } else if macKeys.count < Self.maxKeys {
            macKeys.append(MacKey(keyCode: keyCode, characters: characters, modifiers: modifiers))
        }
    }

    // MARK: - What the press means

    /// Modifiers among the keys the keyboard sent (left and right count the same).
    var modifiers: ModifierSet {
        keys.reduce(into: ModifierSet()) { set, usage in
            if let m = Self.modifier(usage) { set.insert(m) }
        }
    }

    /// The key the press is about: the last non-modifier key, or the first key if all were modifiers.
    var mainKey: HIDUsage? { keys.last { Self.modifier($0) == nil } ?? keys.first }

    /// The device of the first event.
    var device: DeviceRef? { events.first?.device }

    /// The whole press in the order the keys went down, e.g. "⌘ + ⇧ + S".
    var chordDisplay: String {
        keys.map(Self.label).joined(separator: " + ")
    }

    /// True when the keyboard sent several keys for this press.
    var isChord: Bool { keys.count > 1 }

    /// The shortcut macOS would see for this press: what it delivered, else what the keyboard sent.
    var chord: KeyChord? {
        if let mac = macKeys.last { return KeyChord(keyCode: mac.keyCode, modifiers: mac.modifiers.subtracting(.function)) }
        guard let main = mainKey, let code = KeyCatalog.key(for: main)?.macKeyCode else { return nil }
        let mods = Self.modifier(main) == nil ? modifiers : modifiers.subtracting(Self.modifier(main)!)
        return KeyChord(keyCode: code, modifiers: mods)
    }

    /// The keyboard sent keys but macOS delivered nothing to the app, not even a modifier change.
    func macIgnoredIt(now: Date = Date()) -> Bool {
        !events.isEmpty && macKeys.isEmpty && !macSawModifiers && now.timeIntervalSince(start) > 0.4
    }

    static func modifier(_ usage: HIDUsage) -> ModifierSet? {
        usage.page == HIDPage.keyboard ? ChordTracker.modifier(for: usage.usage) : nil
    }

    /// Modifiers the Mac way (⌘ for Win), other keys by their short label.
    static func label(_ usage: HIDUsage) -> String {
        if let m = modifier(usage) { return m.symbols }
        if usage == KeyCatalog.fn { return "fn" }
        return KeyCatalog.key(for: usage)?.label ?? KeyCatalog.name(for: usage)
    }
}
