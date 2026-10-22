# Shift Happens

A native macOS app (SwiftUI) that makes a Windows keyboard work well with a Mac, for everyone who misses
the one-key Print Screen and has to press three keys for a screenshot instead:
it shows the code of every key you press, remaps keys and turns one key combination into another.
Bindings are saved and restored after a restart.

## Features

- **Keyboard.** A drawn MacBook keyboard, or a full-size Windows keyboard via the Mac | Windows switch (both show the same remaps): remapped keys are highlighted in blue and labeled with their new value,
  keys with combos are marked in purple, and keys you are pressing light up green. Click a key to open the editor.
- **Key Monitor.** For the last key press: the HID code (what the keyboard sends), the macOS key code, the character and the keyboard name.
  If the keyboard sent a key that macOS never received, you see it right away.
- **Remaps** (key → key) through the system `hidutil`. Apply them to every keyboard or only to the Windows keyboard,
  so the MacBook's built-in keyboard stays unchanged. Targets include media keys, volume, brightness and Fn.
- **Combos** (shortcut → shortcut), for example `Insert → ⌘V`, `Ctrl+C → ⌘C`, `PrtSc → ⌘⇧4`.
  A combo can also play a **macro**: a list of raw key events (⌘C is ⌘ down, C down, C up, ⌘ up), pauses and typed
  text, recorded from the keyboard (with or without the pauses) or added by hand, played once or repeated while held.
- **Layout Fixer** (based on [Perekluk](https://github.com/abaskalov/perekluk)): typed a word in the wrong layout?
  Press and release the trigger key (either Option by default, or left/right Option, fn 🌐, Caps Lock) on its own.
  The last word is retyped in the next layout and the layout switches; with a selection, the selected text is converted;
  with nothing typed, the layout just switches. Press again to undo. Works with three or more layouts and dead keys.
  Off by default; can also show the current layout (En / Ру) in the menu bar.
- **Mouse buttons as triggers**: a combo can fire on the middle, back or forward mouse button (optionally with
  modifiers), for example Mouse 4 → ⌘[ so the Back button works in Safari and Finder. Left and right clicks are never touched.
- **Presets** in Settings: swap Win and Alt, Print Screen, Home/End like in Windows, Ctrl shortcuts like in Windows.
- **After restart** the app starts in the background (LaunchAgent), reapplies the bindings and lives in the menu bar.
  Bindings are reapplied whenever a keyboard is connected.
- Export and import of settings as JSON. Settings live in `~/Library/Application Support/KeyBindingApp/config.json` (the folder, bundle ID and launch agent
  keep the original KeyBindingApp name, so permissions and bindings survive the rename).

## Building

Needs macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./scripts/build-app.sh
open "build/Shift Happens.app"
```

Move `build/Shift Happens.app` to Applications and launch it from there, so launch at login points to the right place.
You can also open `Package.swift` in Xcode and run it from there.

If the app was downloaded from GitHub Actions, macOS may refuse to open it. Then run
`xattr -dr com.apple.quarantine "/Applications/Shift Happens.app"` or right-click → Open.

`swift scripts/make-icon.swift` redraws the app icon into `Resources/AppIcon.icns`.

## Permissions

On first launch a welcome sheet asks for two permissions; each button shows macOS's own dialog, or opens
System Settings → Privacy & Security if macOS has asked before. Turning on Combos or the Layout Fixer asks for
Accessibility right away. The sheet is also in Settings → Permissions → Show Welcome Guide.

| Permission | Why |
|---|---|
| Input Monitoring | To see key codes and which keyboard they came from |
| Accessibility | To replace key combinations (combos) and to fix the layout of typed text |

Plain remaps through `hidutil` work without either of them.

The app is signed ad hoc, and macOS ties permissions to the signature. After every rebuild the permissions have to be
granted again: System Settings may still show the old entry as on. **Reset and Ask Again** in the app removes that entry
(`tccutil reset`) and asks again. Input Monitoring takes effect after a relaunch; the app offers a **Relaunch** button. To avoid that, sign with your own certificate:
`SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh`.

## Privacy

Nothing you type is recorded, saved or sent anywhere.

- **Key Monitor** shows only the last key press, only while its screen is visible and the app is in front. There is
  no history. It is dropped as soon as you leave the screen, close or minimize the window, or switch to another app.
- **Keyboard screen** highlights held keys only while it is visible. Otherwise key presses from the keyboard are ignored
  as soon as they arrive; "press a key" buttons receive just the one press they ask for.
- **Layout Fixer** has to remember the word being typed to retype it. It holds only that word in memory and forgets it on
  Return, Tab, Escape, a click, switching apps, a new word or when the fixer is turned off. It is never logged or saved.
- `config.json` holds only your bindings and settings.

## How it works

| File | What it does |
|---|---|
| `Services/HIDMonitor.swift` | Reads keyboards through IOHIDManager and watches for connections |
| `Services/RemapEngine.swift` | Applies remaps with `hidutil property --set '{"UserKeyMapping":[...]}'` |
| `Services/ComboEngine.swift` | CGEventTap: catches a combination and sends another one instead |
| `Services/LayoutFixer.swift` | Event tap that buffers the last word and fixes it or the selection on a lone trigger press |
| `Services/InputSources.swift` | Keyboard layouts (TIS) and conversion between them with `UCKeyTranslate` |
| `Services/LaunchAgent.swift` | `~/Library/LaunchAgents/com.keybindingapp.agent.plist`, launched with `--background` |
| `Model/KeyCatalog.swift` | Table of HID codes, macOS key codes and key names |
| `Views/*` | User interface |
| `Debug/Snapshot.swift` | Debug builds only: renders a screen to PNG (`KB_SNAPSHOT=out.png KB_SCREEN=remaps .build/debug/KeyBindingApp`) and runs the layout fixer self-test (`KB_SELFTEST=1 .build/debug/KeyBindingApp`) |

To turn everything off quickly, use the switch in the menu bar. To clear the system remaps by hand:
`hidutil property --set '{"UserKeyMapping":[]}'`.

The layout fixer is adapted from Perekluk (MIT License), see `THIRD_PARTY_NOTICES.md`.
