import AppKit

/// Debug builds only: renders the app's windows to PNG files so the layout can be checked
/// without Screen Recording access. Driven by environment variables:
/// KB_SNAPSHOT=<file.png>, KB_SCREEN=<keyboard|monitor|remaps|combos|settings>,
/// KB_SIZE=<width>x<height>, KB_EDIT=1 (opens the remap editor for Esc on the Keyboard screen).
enum DebugSnapshot {
    #if DEBUG
    private static let env = ProcessInfo.processInfo.environment
    static var initialScreen: SidebarItem? { env["KB_SCREEN"].flatMap(SidebarItem.init(rawValue:)) }
    static var opensEditor: Bool { env["KB_EDIT"] == "1" }
    /// KB_ONBOARDING=1 shows the welcome sheet as on a first launch.
    static var showsOnboarding: Bool { env["KB_ONBOARDING"] == "1" }
    /// While rendering snapshots the app must not ask for permissions or open System Settings.
    static var isActive: Bool { env["KB_SNAPSHOT"] != nil }
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
    static var showsOnboarding: Bool { false }
    static var isActive: Bool { false }
    static var assumesRequested: Bool { false }
    static func runIfRequested(window: NSWindow) {}
    static func runSelfTestIfRequested() {}
    #endif
}
