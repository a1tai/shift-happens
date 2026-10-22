// Fixes text typed in the wrong keyboard layout.
// Ported from Perekluk (https://github.com/abaskalov/perekluk), MIT License,
// Copyright (c) 2025 abaskalov. See THIRD_PARTY_NOTICES.md.
import AppKit
import Carbon
import IOKit.hid
import os

/// Remembers the keys of the word being typed. A lone press of the trigger key then
/// - retypes the last word in the next layout and switches to it,
/// - or converts the selected text if nothing was typed,
/// - or just switches the layout if nothing is selected either.
/// Pressing the trigger again converts back. Needs the Accessibility permission.
final class LayoutFixer {
    /// Diagnostics only: whether the tap runs and what the trigger does. Never which keys were typed.
    private static let log = Logger(subsystem: "com.keybindingapp.KeyBindingApp", category: "LayoutFixer")

    var trigger: LayoutTrigger = .bothOptions {
        didSet { resetTriggerState() }
    }
    /// Checked on every event: while true, keys pass through and nothing is fixed.
    var isPaused: () -> Bool = { false }
    /// Replaces the fixing itself (used by the debug self-test, which must not type anything).
    var fixHandler: ((_ word: [TypedKey], _ trailingSpaces: Int) -> Void)?

    let sources = InputSources()

    /// The keys of the current word (and spaces typed after it). Memory only, never logged or saved;
    /// kept after a fix so a second press can undo it.
    private(set) var buffer: [TypedKey] = []
    private let maxBufferSize = 64
    private var triggerDown = false
    private var triggerAlone = false
    private var lastCapsLockState = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var appObserver: NSObjectProtocol?
    private let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = SyntheticEvent.layoutFixer
        return source
    }()
    private let pasteboard = NSPasteboard.general

    var isRunning: Bool { tap != nil }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << Self.systemDefinedEventType)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let fixer = Unmanaged<LayoutFixer>.fromOpaque(context).takeUnretainedValue()
                return fixer.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            Self.log.error("Event tap could not be created (no Accessibility access?)")
            return false
        }
        Self.log.notice("Event tap started, trigger \(self.trigger.rawValue, privacy: .public), AX trusted \(AXIsProcessTrusted(), privacy: .public), input monitoring \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue, privacy: .public)")
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        resetTriggerState()
        // A word typed in one app must not be "fixed" in another.
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.clearBuffer() }
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        tap = nil
        runLoopSource = nil
        appObserver = nil
        clearBuffer()
    }

    func clearBuffer() { buffer.removeAll(keepingCapacity: true) }

    // MARK: - Event tap

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.log.notice("Event tap disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)), re-enabling")
            // Keys typed while the tap was off never reached the buffer, and a trigger release may be lost.
            clearBuffer()
            resetTriggerState()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch event.getIntegerValueField(.eventSourceUserData) {
        case SyntheticEvent.layoutFixer:
            return Unmanaged.passUnretained(event)
        case SyntheticEvent.combo:
            // A combo just typed something we can't replay, or used the trigger key as a modifier.
            clearBuffer()
            triggerAlone = false
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        if isPaused() {
            if type == .flagsChanged { Self.log.notice("Paused: ignoring modifier change") }
            clearBuffer()
            triggerAlone = false
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == Self.systemDefinedEventType {
            // Media keys arrive as NX_SYSDEFINED: Option+Volume Up is not a lone Option press.
            if triggerDown { triggerAlone = false }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            handleKeyDown(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags)
        case .flagsChanged:
            if handleFlagsChanged(event.flags) { return nil }
        case .leftMouseDown, .rightMouseDown:
            // The caret may have moved: the buffer no longer matches the text before it.
            clearBuffer()
            if triggerDown { triggerAlone = false }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ keyCode: UInt16, flags: CGEventFlags) {
        if triggerDown {
            // A key pressed together with the trigger: a shortcut, not a fix.
            triggerAlone = false
            clearBuffer()
            return
        }
        // ⌘/⌃/⌥ characters (•, ©, dead keys) can't be replayed from key codes.
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
            || Self.wordBoundaryKeys.contains(keyCode) {
            clearBuffer()
            return
        }
        if keyCode == Self.deleteKeyCode {
            if !buffer.isEmpty { buffer.removeLast() }
            return
        }
        guard keyCode <= InputSources.maxPrintableKeyCode else {
            clearBuffer()
            return
        }
        // Only the word being typed is kept: a new word drops the previous one and the spaces after it.
        if keyCode != InputSources.spaceKeyCode && buffer.last?.keyCode == InputSources.spaceKeyCode {
            clearBuffer()
        }
        buffer.append(TypedKey(keyCode: keyCode, shift: flags.contains(.maskShift),
                               capsLock: flags.contains(.maskAlphaShift)))
        if buffer.count > maxBufferSize { buffer.removeFirst(buffer.count - maxBufferSize) }
    }

    /// Returns true when the event must be swallowed (Caps Lock used as the trigger).
    private func handleFlagsChanged(_ flags: CGEventFlags) -> Bool {
        if trigger == .capsLock {
            let capsOn = flags.contains(.maskAlphaShift)
            guard capsOn != lastCapsLockState else { return false }
            lastCapsLockState = capsOn
            fire()
            return true
        }

        let pressed = isTriggerPressed(flags)
        if pressed != triggerDown {
            Self.log.notice("Trigger \(pressed ? "down" : "up", privacy: .public), alone: \(self.triggerAlone, privacy: .public), flags 0x\(String(flags.rawValue, radix: 16), privacy: .public)")
        }
        // Shift/⌘/⌃ with the trigger make it a shortcut. Caps Lock is left out: it stays set while on.
        let chord = !flags.intersection([.maskShift, .maskCommand, .maskControl]).isEmpty
        if pressed && !triggerDown {
            triggerDown = true
            triggerAlone = !chord
        } else if pressed && chord {
            triggerAlone = false
        } else if !pressed && triggerDown {
            if triggerAlone { fire() }
            triggerDown = false
            triggerAlone = false
        }
        return false
    }

    private func isTriggerPressed(_ flags: CGEventFlags) -> Bool {
        switch trigger {
        case .leftOption: return flags.rawValue & Self.deviceLeftAltMask != 0
        case .rightOption: return flags.rawValue & Self.deviceRightAltMask != 0
        case .bothOptions: return flags.contains(.maskAlternate)
        case .fn: return flags.contains(.maskSecondaryFn)
        case .capsLock: return flags.contains(.maskAlphaShift)
        }
    }

    private func resetTriggerState() {
        triggerDown = false
        triggerAlone = false
        // If Caps Lock is already on, its next press turns it off and must still count.
        lastCapsLockState = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    /// The last word in the buffer and the spaces typed after it.
    private func lastWord() -> (word: [TypedKey], trailingSpaces: Int) {
        var end = buffer.count
        while end > 0 && buffer[end - 1].keyCode == InputSources.spaceKeyCode { end -= 1 }
        var start = end
        while start > 0 && buffer[start - 1].keyCode != InputSources.spaceKeyCode { start -= 1 }
        return (Array(buffer[start..<end]), buffer.count - end)
    }

    private func fire() {
        let (word, trailingSpaces) = lastWord()
        Self.log.notice("Fire: word of \(word.count, privacy: .public) keys, current layout \(self.sources.currentID() ?? "?", privacy: .public)")
        if let fixHandler {
            fixHandler(word, trailingSpaces)
            return
        }
        // Leave the tap callback quickly; the work below talks to other apps.
        DispatchQueue.main.async { [self] in
            if word.isEmpty {
                fixSelection()
            } else {
                fixWord(word, trailingSpaces: trailingSpaces)
            }
        }
    }

    // MARK: - Fixing the last word

    private func fixWord(_ word: [TypedKey], trailingSpaces: Int) {
        guard let current = sources.currentID(), let next = sources.nextID(after: current),
              let converted = sources.text(for: word, inLayout: next) else { return }
        let newText = converted + String(repeating: " ", count: trailingSpaces)
        // Dead keys compose, so count the characters on screen, not the keystrokes.
        let deleteCount = (sources.text(for: word, inLayout: current)?.count ?? word.count) + trailingSpaces
        let saved = savePasteboard()
        let delay = Timing.deleteDelay(charCount: deleteCount)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            for _ in 0..<deleteCount { postBackspace() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                paste(newText)
                sources.select(next)
                restorePasteboard(saved, afterCharCount: deleteCount)
            }
        }
    }

    // MARK: - Fixing the selection

    private func fixSelection() {
        if let text = Accessibility.selectedText() {
            convertSelection(text, viaClipboard: false)
            return
        }
        // Some apps don't expose the selection: copy it through the app's own Edit menu.
        let changeCount = pasteboard.changeCount
        let saved = savePasteboard()
        guard Accessibility.performCopy() else {
            sources.selectNext()
            return
        }
        waitForPasteboardChange(from: changeCount) { [self] text in
            // Copy in Finder copies files; pasting their converted names would duplicate them.
            let copiedFiles = pasteboard.string(forType: .fileURL) != nil
            guard let text, !text.isEmpty, !copiedFiles else {
                if pasteboard.changeCount != changeCount { restorePasteboard(saved, afterCharCount: 0) }
                sources.selectNext()
                return
            }
            convertSelection(text, viaClipboard: true, savedClipboard: saved)
        }
    }

    private func convertSelection(_ text: String, viaClipboard: Bool,
                                  savedClipboard: [[(NSPasteboard.PasteboardType, Data)]] = []) {
        let ids = sources.enabled().map(\.id)
        guard let current = sources.currentID(), ids.count >= 2 else {
            sources.selectNext()
            return
        }
        let from: String
        let to: String
        if let detected = sources.detectLayout(of: text, among: ids) {
            from = detected.from
            to = detected.from == current ? detected.to : current
        } else {
            from = current
            to = sources.nextID(after: current) ?? ids.first { $0 != current }!
        }
        guard let converted = sources.convert(text, from: from, to: to) else {
            sources.selectNext()
            return
        }
        if !viaClipboard && Accessibility.replaceSelectedText(with: converted) {
            // Done in place.
        } else {
            paste(converted)
            if viaClipboard { restorePasteboard(savedClipboard, afterCharCount: converted.count) }
        }
        if to != current { sources.select(to) }
    }

    // MARK: - Typing and the clipboard

    private func postBackspace() {
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.deleteKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.deleteKeyCode, keyDown: false) else { return }
        // Terminals need the DEL character to know which byte to send.
        var delete: UniChar = 0x7F
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &delete)
        // Without modifiers, or a terminal reads it as Alt+Backspace (delete word).
        let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        down.flags = down.flags.subtracting(modifiers)
        up.flags = up.flags.subtracting(modifiers)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func paste(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: Self.vKeyCode, keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    private func savePasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    /// Puts the user's clipboard back once the paste has happened, unless something else changed it meanwhile.
    private func restorePasteboard(_ saved: [[(NSPasteboard.PasteboardType, Data)]], afterCharCount count: Int) {
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.clipboardRestoreDelay(charCount: count)) { [self] in
            guard pasteboard.changeCount == changeCount, !saved.isEmpty else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { itemData in
                let item = NSPasteboardItem()
                for (type, data) in itemData { item.setData(data, forType: type) }
                return item
            })
        }
    }

    private func waitForPasteboardChange(from changeCount: Int, attempt: Int = 0, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.pasteboardPollInterval) { [self] in
            if pasteboard.changeCount != changeCount {
                completion(pasteboard.string(forType: .string))
            } else if attempt + 1 < Timing.pasteboardPollMaxAttempts {
                waitForPasteboardChange(from: changeCount, attempt: attempt + 1, completion: completion)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Constants

    /// NX_SYSDEFINED (media and system keys); CGEventType has no case for it.
    private static let systemDefinedEventType: UInt32 = 14
    // Device-level modifier bits from IOLLEvent.h, to tell the left and right Option apart.
    private static let deviceLeftAltMask: UInt64 = 0x20
    private static let deviceRightAltMask: UInt64 = 0x40
    private static let deleteKeyCode: CGKeyCode = 51
    private static let vKeyCode: CGKeyCode = 9
    /// Return, keypad Enter, Tab, Escape.
    private static let wordBoundaryKeys: Set<UInt16> = [36, 76, 48, 53]

    private enum Timing {
        static let pasteboardPollInterval: TimeInterval = 0.02
        static let pasteboardPollMaxAttempts = 10

        static func deleteDelay(charCount: Int) -> TimeInterval {
            0.03 + 0.003 * TimeInterval(max(0, charCount - 1))
        }

        static func clipboardRestoreDelay(charCount: Int) -> TimeInterval {
            0.2 + 0.005 * TimeInterval(max(0, charCount - 1))
        }
    }

    // MARK: - System settings

    /// "Press 🌐 key to" in System Settings > Keyboard is set to "Do Nothing". Otherwise macOS
    /// also reacts to a lone fn press and the layout would switch twice.
    static var globeKeyDoesNothing: Bool {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int == 0
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Reads and writes the focused text field's selection in other apps.
private enum Accessibility {
    static func selectedText() -> String? {
        guard let focused = focusedElement(),
              let text: String = attribute(kAXSelectedTextAttribute, of: focused), !text.isEmpty else { return nil }
        return text
    }

    static func replaceSelectedText(with text: String) -> Bool {
        guard let focused = focusedElement() else { return false }
        return AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    /// Presses the frontmost app's Edit > Copy. A synthetic ⌘C is avoided on purpose: terminals such as
    /// Ghostty pass an unhandled ⌘C to the shell, which would type a stray "c".
    /// Returns false when there is no enabled Copy item, which usually means nothing is selected.
    static func performCopy() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar: AXUIElement = attribute(kAXMenuBarAttribute, of: appElement),
              let item = copyItem(in: menuBar),
              let enabled: Bool = attribute(kAXEnabledAttribute, of: item), enabled else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Edit is the fourth menu in nearly every app, so look there first and then at its neighbours.
    private static func copyItem(in menuBar: AXUIElement) -> AXUIElement? {
        guard let menus: [AXUIElement] = attribute(kAXChildrenAttribute, of: menuBar) else { return nil }
        let editIndex = 3
        for index in menus.indices.sorted(by: { abs($0 - editIndex) < abs($1 - editIndex) }) {
            guard let submenus: [AXUIElement] = attribute(kAXChildrenAttribute, of: menus[index]),
                  let submenu = submenus.first,
                  let items: [AXUIElement] = attribute(kAXChildrenAttribute, of: submenu) else { continue }
            if let item = items.first(where: isCopyItem) { return item }
        }
        return nil
    }

    /// AppKit apps expose the copy: selector; Electron/Qt menus have a plain ⌘C equivalent;
    /// the title covers apps that handle ⌘C themselves and leave the item without one.
    private static func isCopyItem(_ item: AXUIElement) -> Bool {
        if let identifier: String = attribute(kAXIdentifierAttribute, of: item), identifier == "copy:" { return true }
        let key: String? = attribute(kAXMenuItemCmdCharAttribute, of: item)
        let modifiers: Int? = attribute(kAXMenuItemCmdModifiersAttribute, of: item)
        if key?.uppercased() == "C" && modifiers == 0 { return true }
        let title: String? = attribute(kAXTitleAttribute, of: item)
        return title.map(copyTitles.contains) ?? false
    }

    private static let copyTitles: Set<String> = [
        "Copy", "Скопировать", "Копировать", "Копіювати", "Kopieren", "Copier", "Copiar", "Copia",
        "Kopiuj", "Kopiëren", "Kopiera", "Kopiér", "Kopioi", "Kopyala", "Másolás", "Kopírovat",
        "拷贝", "复制", "拷貝", "複製", "コピー", "복사",
    ]

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
