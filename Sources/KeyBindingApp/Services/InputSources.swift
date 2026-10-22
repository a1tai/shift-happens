// Keyboard layout lookup and text conversion between layouts.
// Ported from Perekluk (https://github.com/abaskalov/perekluk), MIT License,
// Copyright (c) 2025 abaskalov. See THIRD_PARTY_NOTICES.md.
import Carbon

/// One enabled keyboard layout (input source) as shown in the UI.
struct InputSourceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String?

    /// Short menu bar label: "Ру" for Russian, otherwise the capitalized language code ("En", "De").
    var shortLabel: String {
        guard let language else { return String(name.prefix(2)) }
        return language.hasPrefix("ru") ? "Ру" : String(language.prefix(2)).capitalized
    }
}

/// A key press as typed: a macOS virtual key code plus the state that changes the character.
struct TypedKey: Equatable {
    let keyCode: UInt16
    let shift: Bool
    let capsLock: Bool
}

/// Wraps the Text Input Sources API: lists and switches layouts and converts keystrokes or text
/// from one layout to another with UCKeyTranslate.
final class InputSources {
    /// Virtual key codes 0...50 cover every character key on the main block.
    static let maxPrintableKeyCode: UInt16 = 50
    static let spaceKeyCode: UInt16 = 49

    // Keeps the CFData alive: TISGetInputSourceProperty returns memory owned by the source.
    private var layoutCache: [String: CFData] = [:]

    func invalidateCache() { layoutCache.removeAll() }

    // MARK: - Listing and switching

    func enabled() -> [InputSourceInfo] {
        // Sorted by ID: the same order nextID(after:) cycles through.
        enabledSources().compactMap { source in
            guard let id = id(of: source) else { return nil }
            return InputSourceInfo(id: id, name: string(kTISPropertyLocalizedName, of: source) ?? id,
                                   language: languages(of: source).first)
        }
        .sorted { $0.id < $1.id }
    }

    func currentID() -> String? {
        TISCopyCurrentKeyboardInputSource().flatMap { id(of: $0.takeRetainedValue()) }
    }

    func select(_ id: String) {
        if let source = source(withID: id) { TISSelectInputSource(source) }
    }

    /// The layout after `currentID` in a stable order, so repeated triggers cycle through 3+ layouts.
    func nextID(after currentID: String) -> String? {
        let ids = enabledSources().compactMap(id(of:)).sorted()
        guard let index = ids.firstIndex(of: currentID) else { return ids.first { $0 != currentID } }
        let next = ids[(index + 1) % ids.count]
        return next == currentID ? nil : next
    }

    func selectNext() {
        if let current = currentID(), let next = nextID(after: current) { select(next) }
    }

    // MARK: - Conversion

    /// Retypes keystrokes through the layout `id`, dead keys included (^ + e → ê).
    func text(for keys: [TypedKey], inLayout id: String) -> String? {
        guard let layout = source(withID: id).flatMap(layoutData) else { return nil }
        var deadKeyState: UInt32 = 0
        var result = ""
        for key in keys {
            result += translate(key.keyCode, shift: key.shift, capsLock: key.capsLock, layout: layout,
                                deadKeyState: &deadKeyState)
        }
        if deadKeyState != 0 {
            // A trailing dead key is flushed with Space, which prints the accent itself.
            result += translate(Self.spaceKeyCode, shift: false, capsLock: false, layout: layout,
                                deadKeyState: &deadKeyState)
        }
        return result.isEmpty ? nil : result
    }

    /// Converts text as if the same keys had been pressed in another layout. Characters that the
    /// source layout cannot type stay as they are.
    func convert(_ text: String, from fromID: String, to toID: String) -> String? {
        guard let from = source(withID: fromID).flatMap(layoutData),
              let to = source(withID: toID).flatMap(layoutData) else { return nil }
        var keys: [String: (keyCode: UInt16, shift: Bool)] = [:]
        for keyCode in 0...Self.maxPrintableKeyCode {
            for shift in [false, true] {
                if let char = character(keyCode, shift: shift, layout: from) { keys[char] = (keyCode, shift) }
            }
        }
        var result = ""
        for char in text {
            let s = String(char)
            if let key = keys[s], let converted = character(key.keyCode, shift: key.shift, layout: to) {
                result += converted
            } else {
                result += s
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Guesses which layout `text` was typed in by counting characters that only one layout has.
    /// Returns the best layout and the runner-up, or nil when it is a tie.
    func detectLayout(of text: String, among ids: [String]) -> (from: String, to: String)? {
        var characters: [String: Set<String>] = [:]
        for id in ids {
            guard let layout = source(withID: id).flatMap(layoutData) else { continue }
            var set = Set<String>()
            for keyCode in 0...Self.maxPrintableKeyCode {
                for shift in [false, true] {
                    if let char = character(keyCode, shift: shift, layout: layout) { set.insert(char) }
                }
            }
            characters[id] = set
        }
        let scores: [(id: String, score: Int)] = ids.map { id in
            let others = ids.filter { $0 != id }.reduce(into: Set<String>()) { $0.formUnion(characters[$1] ?? []) }
            let unique = (characters[id] ?? []).subtracting(others)
            return (id, text.filter { unique.contains(String($0)) }.count)
        }.sorted { $0.score > $1.score }
        guard scores.count >= 2, scores[0].score > 0, scores[0].score != scores[1].score else { return nil }
        return (scores[0].id, scores[1].id)
    }

    // MARK: - TIS helpers

    private func enabledSources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true as Any,
        ] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    private func source(withID id: String) -> TISInputSource? {
        enabledSources().first { self.id(of: $0) == id }
    }

    private func id(of source: TISInputSource) -> String? {
        string(kTISPropertyInputSourceID, of: source)
    }

    private func string(_ key: CFString, of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func languages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
    }

    private func layoutData(_ source: TISInputSource) -> UnsafePointer<UCKeyboardLayout>? {
        let data: CFData
        if let id = id(of: source), let cached = layoutCache[id] {
            data = cached
        } else {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            if let id = id(of: source) { layoutCache[id] = data }
        }
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    }

    /// The character a single key produces, ignoring dead keys.
    private func character(_ keyCode: UInt16, shift: Bool, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeyState: UInt32 = 0
        let s = translate(keyCode, shift: shift, capsLock: false, layout: layout, deadKeyState: &deadKeyState,
                          options: OptionBits(kUCKeyTranslateNoDeadKeysMask))
        return s.isEmpty ? nil : s
    }

    private func translate(_ keyCode: UInt16, shift: Bool, capsLock: Bool, layout: UnsafePointer<UCKeyboardLayout>,
                           deadKeyState: inout UInt32, options: OptionBits = 0) -> String {
        var modifiers: UInt32 = 0
        if shift { modifiers |= UInt32(shiftKey >> 8) & 0xFF }
        if capsLock { modifiers |= UInt32(alphaLock >> 8) & 0xFF }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                    options, &deadKeyState, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: chars, count: length)
    }
}
