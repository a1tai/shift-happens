import AppKit
import IOKit.hid

/// Debug builds only: renders the app's windows to PNG files so the layout can be checked
/// without Screen Recording access. Driven by environment variables:
/// KB_SNAPSHOT=<file.png>, KB_SCREEN=<keyboard|monitor|remaps|combos|settings>,
/// KB_SIZE=<width>x<height>, KB_EDIT=1 (opens the remap editor for Esc on the Keyboard screen).
enum DebugSnapshot {
    #if DEBUG
    private static let env = ProcessInfo.processInfo.environment
    static var initialScreen: SidebarItem? { env["KB_SCREEN"].flatMap(SidebarItem.init(rawValue:)) }
    static var opensEditor: Bool { env["KB_EDIT"] == "1" }
    /// KB_EDIT=combo on the Combos screen opens the combo editor with PrtSc → ⌘⇧4.
    static var opensComboEditor: Bool { env["KB_EDIT"] == "combo" }
    /// KB_EDIT=macro on the Combos screen opens the combo editor with a sample macro.
    static var opensMacroEditor: Bool { env["KB_EDIT"] == "macro" }
    /// KB_ONBOARDING=1 shows the welcome sheet as on a first launch.
    static var showsOnboarding: Bool { env["KB_ONBOARDING"] == "1" }
    /// While rendering snapshots the app must not ask for permissions or open System Settings.
    static var isActive: Bool { env["KB_SNAPSHOT"] != nil }
    /// KB_NO_BANNER=1 hides the permission banners, to check layouts as they look once permissions are granted.
    static var hidesBanners: Bool { env["KB_NO_BANNER"] == "1" }

    private static var lastKeyboardFit: (drawn: CGSize, available: CGSize)?
    static func recordKeyboardFit(drawn: CGSize, available: CGSize) { lastKeyboardFit = (drawn, available) }

    private static var recorded: [(String, CGFloat)] = []
    /// Notes a measured value for the snapshot report.
    static func record(_ name: String, _ value: CGFloat) { recorded.append((name, value)) }

    /// KB_REQUESTED=1 renders permissions as if macOS had asked before (the "Reset and Ask Again" state).
    static var assumesRequested: Bool { env["KB_REQUESTED"] == "1" }

    static func runIfRequested(window: NSWindow) {
        guard let path = env["KB_SNAPSHOT"] else { return }
        if let size = env["KB_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            window.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let target = window.attachedSheet ?? window
            guard let view = target.contentView?.superview ?? target.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let fit = lastKeyboardFit {
                let fits = fit.drawn.width <= fit.available.width + 0.5 && fit.drawn.height <= fit.available.height + 0.5
                print("KEYBOARD \(fits ? "FITS" : "OVERFLOWS"): drawn \(Int(fit.drawn.width))×\(Int(fit.drawn.height)) "
                      + "in \(Int(fit.available.width))×\(Int(fit.available.height))")
            }
            // Scroll views in the detail area (the sidebar list is one too, on the left).
            let sidebarEdge: CGFloat = 260
            func scrollViews(in view: NSView) -> [NSScrollView] {
                let own = (view as? NSScrollView).map { [$0] } ?? []
                return own + view.subviews.flatMap(scrollViews)
            }
            let detailScrollers = scrollViews(in: view).filter {
                $0.convert($0.bounds, to: nil).minX > sidebarEdge && !$0.isHidden && $0.frame.width > 0
            }
            print("SCROLL VIEWS IN DETAIL: \(detailScrollers.count)")
            for (name, value) in recorded { print("MEASURED \(name): \(Int(value))") }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
    /// KB_SELFTEST=1: checks the layout fixer's logic and config decoding, prints the results and exits.
    /// Nothing is typed or switched: events are fed straight into the fixer's handler.
    static func runSelfTestIfRequested() {
        guard env["KB_SELFTEST"] == "1" else { return }
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print((ok ? "PASS " : "FAIL ") + name + (ok ? "" : "  " + detail()))
            if !ok { failures += 1 }
        }

        // Conversion with the layouts enabled on this Mac.
        let sources = InputSources()
        let ids = sources.enabled().map(\.id)
        print("Layouts: \(ids)")
        let latin = ids.first { $0.hasSuffix(".ABC") || $0.hasSuffix(".US") }
        let cyrillic = ids.first { $0.contains("Russian") }
        if let latin, let cyrillic {
            let keys = "ghbdtn".map { key(for: $0) }
            check("keys → Russian", sources.text(for: keys, inLayout: cyrillic) == "\u{43F}\u{440}\u{438}\u{432}\u{435}\u{442}",
                  sources.text(for: keys, inLayout: cyrillic) ?? "nil")
            check("keys → Latin", sources.text(for: keys, inLayout: latin) == "ghbdtn")
            let shifted = [TypedKey(keyCode: 5, shift: true, capsLock: false)] + keys.dropFirst()
            check("shift is kept", sources.text(for: shifted, inLayout: cyrillic)?.first == "\u{41F}")
            let russianHello = "\u{440}\u{443}\u{434}\u{434}\u{449}"
            check("convert Russian → Latin", sources.convert(russianHello, from: cyrillic, to: latin) == "hello",
                  sources.convert(russianHello, from: cyrillic, to: latin) ?? "nil")
            check("convert Latin → Russian", sources.convert("hello", from: latin, to: cyrillic) == russianHello)
            check("unknown characters stay", sources.convert("1 + 2 ✓", from: latin, to: cyrillic)?.hasSuffix("✓") == true)
            check("detect Russian", sources.detectLayout(of: russianHello, among: ids)?.from == cyrillic)
            check("detect Latin", sources.detectLayout(of: "ghbdtn", among: ids)?.from == latin)
            check("next layout cycles", sources.nextID(after: latin) == cyrillic && sources.nextID(after: cyrillic) == latin)
        } else {
            print("SKIP conversion checks: needs ABC/US and a Russian layout enabled")
        }

        // Trigger detection.
        let fixer = LayoutFixer()
        var fixed: [(word: String, spaces: Int)] = []
        fixer.fixHandler = { word, spaces in fixed.append((word.map { String($0.keyCode) }.joined(separator: ","), spaces)) }
        func type(_ text: String) { for c in text { keyDown(key(for: c)) } }
        func keyDown(_ key: TypedKey, flags: CGEventFlags = [], marker: Int64 = 0) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key.keyCode, keyDown: true)!
            event.flags = key.shift ? flags.union(.maskShift) : flags
            if marker != 0 { event.setIntegerValueField(.eventSourceUserData, value: marker) }
            _ = fixer.handle(type: .keyDown, event: event)
        }
        func flags(_ flags: CGEventFlags, raw: UInt64 = 0) -> Bool {
            let event = CGEvent(source: nil)!
            event.type = .flagsChanged
            event.flags = CGEventFlags(rawValue: flags.rawValue | raw)
            return fixer.handle(type: .flagsChanged, event: event) == nil
        }
        func tapOption(raw: UInt64 = 0x20) { _ = flags(.maskAlternate, raw: raw); _ = flags([]) }
        func expect(_ name: String, word: String?, spaces: Int = 0) {
            let got = fixed.last
            if let word {
                let keys = word.map { String(key(for: $0).keyCode) }.joined(separator: ",")
                check(name, fixed.count == 1 && got?.word == keys && got?.spaces == spaces, "\(fixed)")
            } else {
                check(name, fixed.isEmpty, "\(fixed)")
            }
            fixed.removeAll()
            fixer.clearBuffer()
        }

        type("ghbdtn"); tapOption(); expect("lone Option fixes the word", word: "ghbdtn")
        type("ab  "); tapOption(); expect("trailing spaces are kept", word: "ab", spaces: 2)
        type("one two")
        check("buffer holds only the current word", fixer.buffer.count == 3, "\(fixer.buffer.count) keys")
        tapOption(); expect("only the last word", word: "two")
        type("abc"); keyDown(TypedKey(keyCode: 51, shift: false, capsLock: false)); tapOption()
        expect("backspace removes a key", word: "ab")
        type("abc"); keyDown(TypedKey(keyCode: 36, shift: false, capsLock: false)); tapOption()
        expect("Return ends the word", word: "")
        type("abc"); _ = flags(.maskAlternate, raw: 0x20); keyDown(key(for: "x"), flags: .maskAlternate); _ = flags([])
        expect("Option+key is a shortcut", word: nil)
        type("abc"); _ = flags(.maskAlternate, raw: 0x20); _ = flags([.maskAlternate, .maskShift], raw: 0x20); _ = flags([])
        expect("Option+Shift is a shortcut", word: nil)
        type("abc"); _ = flags(.maskAlternate, raw: 0x20)
        keyDown(key(for: "v"), flags: .maskCommand, marker: SyntheticEvent.combo); _ = flags([])
        expect("a combo firing cancels the trigger", word: nil)
        type("abc"); keyDown(key(for: "z"), marker: SyntheticEvent.layoutFixer); tapOption()
        expect("own events are not buffered", word: "abc")
        fixer.trigger = .leftOption
        type("abc"); tapOption(raw: 0x40); expect("right Option ignored for left trigger", word: nil)
        type("abc"); tapOption(raw: 0x20); expect("left Option fires for left trigger", word: "abc")
        fixer.trigger = .capsLock
        type("abc"); let swallowed = flags(.maskAlphaShift)
        check("Caps Lock press is swallowed", swallowed)
        expect("Caps Lock fires", word: "abc")
        fixer.trigger = .bothOptions
        fixer.isPaused = { true }
        type("abc"); tapOption(); expect("paused fixer does nothing", word: nil)

        // Keyboards connected to this Mac, as the pickers will list them.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
        ] as CFArray)
        let keyboards = HIDMonitor.keyboards(in: IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
        print("Keyboards: \(keyboards.map { "\($0.name) [\($0.id)]" })")
        check("no headset in keyboards", !keyboards.contains { $0.name == "Headset" })

        // The built-in keyboard (vendor/product 0) never matches other 0/0 parts.
        let builtIn = DeviceRef(vendorID: 0, productID: 0, name: "MacBook keyboard (built-in)", isBuiltIn: true)
        let headset = DeviceRef(vendorID: 0, productID: 0, name: "Headset")
        check("built-in ≠ other 0:0 device", !builtIn.matches(headset) && builtIn.id != headset.id)
        check("built-in matched by flag", RemapEngine.matchingJSON(builtIn).contains("Built-In"))
        let oldDevice = #"{"vendorID":1133,"productID":45077,"name":"K"}"#
        check("old device entries decode", (try? JSONDecoder().decode(DeviceRef.self, from: Data(oldDevice.utf8)))?.isBuiltIn == false)

        // Recording a shortcut from raw key presses.
        var tracker = ChordTracker()
        func hid(_ u: UInt32) -> HIDUsage { HIDUsage(page: HIDPage.keyboard, usage: u) }
        _ = tracker.handle(hid(0xE3), isDown: true)
        _ = tracker.handle(hid(0xE1), isDown: true)
        let screenshot = tracker.handle(hid(0x21), isDown: true)
        check("⌘⇧4 recorded from raw keys", screenshot == KeyChord(keyCode: 0x15, modifiers: [.command, .shift]),
              "\(String(describing: screenshot))")
        tracker = ChordTracker()
        _ = tracker.handle(hid(0xE6), isDown: true)
        _ = tracker.handle(hid(0xE6), isDown: false)
        check("released modifier is not part of the shortcut",
              tracker.handle(hid(0x04), isDown: true) == KeyChord(keyCode: 0x00, modifiers: []))
        check("modifier alone records nothing", ChordTracker().modifierOnlyIsNil())
        check("system shortcut switch is available on this macOS", SystemShortcuts.isAvailable)

        // Macro recording: down+up collapse into one press, modifiers fold in, pauses become delays.
        let t0 = Date(timeIntervalSince1970: 1000)
        func at(_ ms: Double) -> Date { t0.addingTimeInterval(ms / 1000) }
        var rec = MacroRecorder(recordsDelays: true)
        rec.handle(hid(0xE3), isDown: true, at: at(0))      // ⌘ down
        rec.handle(hid(0x06), isDown: true, at: at(10))     // C
        rec.handle(hid(0x06), isDown: false, at: at(60))
        rec.handle(hid(0xE3), isDown: false, at: at(80))
        rec.handle(hid(0x19), isDown: true, at: at(330))    // V after 250 ms
        rec.handle(hid(0x19), isDown: false, at: at(380))
        check("recorded ⌘C, 250 ms, V", rec.steps == [.press(KeyChord(keyCode: 0x08, modifiers: .command)), .delay(250),
                                                     .press(KeyChord(keyCode: 0x09, modifiers: []))], "\(rec.steps)")
        var noDelays = MacroRecorder(recordsDelays: false)
        noDelays.handle(hid(0x04), isDown: true, at: at(0)); noDelays.handle(hid(0x04), isDown: false, at: at(5))
        noDelays.handle(hid(0x05), isDown: true, at: at(900)); noDelays.handle(hid(0x05), isDown: false, at: at(950))
        check("no delays when off", !noDelays.steps.contains { $0.isDelay } && noDelays.steps.count == 2)
        var hold = MacroRecorder(recordsDelays: false)
        hold.handle(hid(0x04), isDown: true, at: at(0)); hold.handle(hid(0x05), isDown: true, at: at(10))
        hold.handle(hid(0x05), isDown: false, at: at(20)); hold.handle(hid(0x04), isDown: false, at: at(30))
        check("overlapping keys stay down/up", hold.steps == [.keyDown(KeyChord(keyCode: 0x00, modifiers: [])),
                                                              .press(KeyChord(keyCode: 0x0B, modifiers: [])),
                                                              .keyUp(KeyChord(keyCode: 0x00, modifiers: []))], "\(hold.steps)")
        var lone = MacroRecorder(recordsDelays: false)
        lone.handle(hid(0xE1), isDown: true, at: at(0)); lone.handle(hid(0xE1), isDown: false, at: at(50))
        check("lone modifier is a press", lone.steps == [.press(KeyChord(keyCode: 0x38, modifiers: []))], "\(lone.steps)")

        var twice = MacroRecorder(recordsDelays: true)
        twice.handle(hid(0x0A), isDown: true, at: at(0)); twice.handle(hid(0x0A), isDown: true, at: at(70))
        twice.handle(hid(0x0A), isDown: false, at: at(100)); twice.handle(hid(0x0A), isDown: false, at: at(101))
        check("a key reported twice is one press", twice.steps == [.press(KeyChord(keyCode: 0x05, modifiers: []))], "\(twice.steps)")
        let messy = [MacroStep.keyDown(KeyChord(keyCode: 5, modifiers: [])), .delay(10), .keyUp(KeyChord(keyCode: 5, modifiers: [])),
                     .delay(250), .press(KeyChord(keyCode: 9, modifiers: .command))].map { MacroItem(step: $0) }
        check("simplify", messy.simplified(minimumDelay: 30).map(\.step) == [.press(KeyChord(keyCode: 5, modifiers: [])), .delay(250),
                                                                         .press(KeyChord(keyCode: 9, modifiers: .command))])

        // Saving macros, and combos saved before macros existed.
        var macroCombo = ComboBinding(trigger: KeyChord(keyCode: 0x69, modifiers: []), output: KeyChord(keyCode: 0, modifiers: []))
        macroCombo.macro = rec.steps.map { MacroItem(step: $0) } + [MacroItem(step: .text("Hi")),
                                                                    MacroItem(step: .keyDown(KeyChord(keyCode: 0x38, modifiers: [])))]
        macroCombo.stepDelay = 20
        let decodedCombo = (try? JSONEncoder().encode(macroCombo)).flatMap { try? JSONDecoder().decode(ComboBinding.self, from: $0) }
        check("macro round-trip", decodedCombo == macroCombo)
        let oldCombo = #"{"id":"21111111-1111-1111-1111-111111111111","trigger":{"keyCode":105,"modifiers":0},"output":{"keyCode":21,"modifiers":12},"note":"","enabled":true}"#
        let decodedOld = try? JSONDecoder().decode(ComboBinding.self, from: Data(oldCombo.utf8))
        check("old combo loads as a shortcut", decodedOld?.isMacro == false && decodedOld?.output.keyCode == 21)
        check("summary", macroCombo.outputSummary == "⌘C · 250 ms · V · “Hi” · Shift down", macroCombo.outputSummary)

        // Playback: order, delays, and every held key released at the end.
        final class FakePoster: KeyEventPosting {
            var log: [String] = []
            func key(_ keyCode: UInt16, down: Bool, modifiers: ModifierSet) { log.append("\(modifiers.symbols)\(keyCode)\(down ? "↓" : "↑")") }
            func text(_ text: String) { log.append("text:\(text)") }
            func wait(milliseconds: Int) { log.append("wait:\(milliseconds)") }
        }
        let fake = FakePoster()
        MacroPlayer.run(macroCombo.macro.map(\.step), stepDelay: 20, poster: fake) { false }
        check("playback order and timing", fake.log == ["⌘8↓", "⌘8↑", "wait:250", "9↓", "9↑", "wait:20", "text:Hi", "wait:20",
                                                         "56↓", "56↑"], "\(fake.log)")
        let cancelled = FakePoster()
        var calls = 0
        MacroPlayer.run([.keyDown(KeyChord(keyCode: 0x38, modifiers: [])), .delay(10), .press(KeyChord(keyCode: 0, modifiers: []))],
                        stepDelay: 0, poster: cancelled) { calls += 1; return calls > 2 }
        check("cancelled macro releases held keys", cancelled.log == ["56↓", "wait:10", "56↑"], "\(cancelled.log)")

        // Config files from before the layout fixer still load.
        let old = #"{"enabled":true,"remaps":[],"combos":[],"knownDevices":[]}"#
        let decoded = try? JSONDecoder().decode(AppConfig.self, from: Data(old.utf8))
        check("old config decodes", decoded?.layoutFixer == LayoutFixerSettings())
        var config = AppConfig()
        config.layoutFixer.enabled = true
        config.layoutFixer.trigger = .rightOption
        let roundTrip = (try? ConfigStore.encode(config)).flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }
        check("layout fixer settings round-trip", roundTrip == config)

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// The ANSI key that types `c` in the US layout.
    private static func key(for c: Character) -> TypedKey {
        let codes: [Character: UInt16] = ["a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "g": 5, "h": 4, "l": 37, "n": 45,
                                          "o": 31, "t": 17, "v": 9, "w": 13, "x": 7, "z": 6, " ": 49]
        return TypedKey(keyCode: codes[c]!, shift: false, capsLock: false)
    }
    #else
    static var initialScreen: SidebarItem? { nil }
    static var opensEditor: Bool { false }
    static var opensComboEditor: Bool { false }
    static var opensMacroEditor: Bool { false }
    static var showsOnboarding: Bool { false }
    static var isActive: Bool { false }
    static var assumesRequested: Bool { false }
    static var hidesBanners: Bool { false }
    static func recordKeyboardFit(drawn: CGSize, available: CGSize) {}
    static func record(_ name: String, _ value: CGFloat) {}
    static func runIfRequested(window: NSWindow) {}
    static func runSelfTestIfRequested() {}
    #endif
}

#if DEBUG
private extension ChordTracker {
    func modifierOnlyIsNil() -> Bool {
        var copy = self
        return copy.handle(HIDUsage(page: HIDPage.keyboard, usage: 0xE3), isDown: true) == nil
    }
}
#endif
