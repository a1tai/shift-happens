# Shift Happens

A native macOS app for people who use a Windows keyboard (or just miss Windows habits) on a Mac —
and who can't get over pressing three keys for a screenshot that used to take one.

It shows what every key really sends, remaps keys, turns shortcuts (or mouse buttons) into other
shortcuts or whole macros, and fixes text typed in the wrong keyboard layout. Everything is set up in
a regular macOS window and lives in the menu bar afterwards.

![Keyboard screen](docs/screenshots/keyboard.png)

| Combo editor | Macro editor |
|---|---|
| ![Combo that opens an app](docs/screenshots/combo-app.png) | ![Macro steps](docs/screenshots/combo-macro.png) |

## Features

- **Keyboard** — a drawn MacBook keyboard, or a full-size Windows keyboard via the Mac | Windows switch.
  Remapped keys are blue and show their new value, keys with combos are purple, keys you press light up.
  Click a key to remap it.
- **Key Monitor** — the last key press: the HID code the keyboard sent, the macOS key code, the character
  and the keyboard. If macOS ignores a key, you see it here. A special key that sends a whole shortcut
  (Win+Shift+S, Ctrl+Alt+X) shows as one press: the full chord and every HID event in order.
- **Remaps** (key → key) through the system's `hidutil`, for every keyboard or just one (so the MacBook's
  own keyboard can stay as it is).
- **Combos** — a key, a shortcut or an extra mouse button (middle, back, forward) sends another shortcut,
  or plays a **macro**: key down / key up events, delays and typed text, recorded from the keyboard or
  edited by hand. Example: `PrtSc → ⌘⇧4`, or `Mouse 4 → ⌘[` so the Back button works in Safari and Finder.
  A combo can also **open an app** (or bring it to the front, and optionally hide it if it already is),
  and a macro can open an app as one of its steps.
- **Actions** — a combo can **paste as plain text** (the clipboard's text without fonts, colors or links, in
  any app; the clipboard is put back right after) or **run a shortcut** from the Shortcuts app.
- **Layout Fixer** — typed `ghbdtn` instead of `привет`? Press the trigger key on its own (either Option,
  left/right Option, fn 🌐 or Caps Lock) and the last word, or the selected text, is retyped in the right
  layout. Works with three or more layouts. Adapted from [Perekluk](https://github.com/abaskalov/perekluk).
- **Input language in the menu bar** — EN / RU next to the app's icon, with a menu to switch layouts and
  open Emoji & Symbols, so macOS's own input menu can be hidden.
- **Presets** for Windows keyboards (swap Win/Alt for one keyboard or all, Print Screen, Home/End, Ctrl
  shortcuts) and for mouse Back/Forward.
- **Active / Paused** — one switch (sidebar or menu bar) pauses everything at once.
- Launch at login, settings export and import.

## Install

Download `Shift-Happens.zip` from [Releases](https://github.com/a1tai/shift-happens/releases), unzip it and move
**Shift Happens** to Applications.

The release build is not notarized, so macOS warns on first open. Open it anyway with right-click → Open,
or in System Settings → Privacy & Security → **Open Anyway**, or with
`xattr -dr com.apple.quarantine "/Applications/Shift Happens.app"`.

Releases are signed with the same (self-signed) certificate every time, so the Input Monitoring and
Accessibility permissions stay when you update. Coming from 1.0.0 or 1.0.1, allow them once more: remove the
old Shift Happens entries in System Settings → Privacy & Security and allow the new one.

Requires macOS 13 or later.

Found a bug or have an idea? Open an [issue](https://github.com/a1tai/shift-happens/issues).

## Permissions

On first launch a welcome sheet asks for two permissions. Each button shows macOS's own dialog (or opens
System Settings → Privacy & Security if macOS has asked before).

| Permission | Needed for |
|---|---|
| Input Monitoring | Key codes in the Key Monitor, recording keys and macros, telling keyboards apart, fn as the Layout Fixer trigger |
| Accessibility | Combos, macros, mouse buttons and the Layout Fixer |

Plain remaps work without either.

## Privacy

Nothing you type is recorded, saved or sent anywhere. The app has no network access.

- **Key Monitor** keeps only the last key press, in memory, while its screen is visible. No history.
- **Keyboard screen** highlights held keys only while it is visible.
- **Recorders** take exactly the keys you record.
- **Layout Fixer** remembers only the word being typed, in memory, to retype it; it forgets it on Return,
  Tab, Escape, a click, an app switch or a new word. To fix a selection it uses the clipboard briefly and
  puts your clipboard back afterwards.
- The settings file (`~/Library/Application Support/Shift Happens/config.json`) holds your bindings,
  including any text you put in macros.

## Build from source

Needs macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./scripts/build-app.sh          # builds "build/Shift Happens.app" and a zip
open "build/Shift Happens.app"
```

macOS ties permissions to the app's signature, and an ad-hoc signature changes with every build. To keep
your permissions across rebuilds, sign with a certificate from your keychain (a free "Apple Development"
certificate works): `SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh`, or put the
identity's name in a git-ignored `.signing-identity` file.

Debug builds have a self-test (`swift build && KB_SELFTEST=1 .build/debug/ShiftHappens`) and can render
any screen to PNG (`KB_SNAPSHOT=out.png KB_SCREEN=combos .build/debug/ShiftHappens`). The icon is drawn by
`swift scripts/make-icon.swift`.

## Uninstall

1. Quit Shift Happens from its menu bar menu (its remaps stay active until a restart; to drop them now:
   `hidutil property --set '{"UserKeyMapping":[]}'`).
2. Delete the app, `~/Library/Application Support/Shift Happens` and, if launch at login was on,
   `~/Library/LaunchAgents/io.github.a1tai.ShiftHappens.agent.plist`.
3. Remove it from System Settings → Privacy & Security → Input Monitoring and Accessibility.

## How it works

| Part | What it does |
|---|---|
| `Services/RemapEngine.swift` | Key → key remaps with `hidutil property --set '{"UserKeyMapping":[…]}'` |
| `Services/ComboEngine.swift` | Event tap that replaces shortcuts and mouse buttons; plays macros |
| `Services/LayoutFixer.swift`, `InputSources.swift` | Layout fixing with `UCKeyTranslate` |
| `Services/HIDMonitor.swift` | Reads keyboards with IOHIDManager (key codes, fn, devices) |
| `Services/LaunchAgent.swift` | Launch at login via `~/Library/LaunchAgents` |

The fn / 🌐 key can't be remapped or sent by apps, so it isn't offered for remaps, combos or macros; it can
still be the Layout Fixer trigger. While a shortcut is being recorded, macOS's own shortcuts (⌘⇧4, ⌘Space…)
are switched off through a private API (`CGSSetGlobalHotKeyOperatingMode`) and switched back on right after.

## License

MIT, see [LICENSE](LICENSE). The Layout Fixer is adapted from Perekluk (MIT), see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
