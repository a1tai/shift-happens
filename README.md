# KeyBindingApp

A native macOS app (SwiftUI) that makes a Windows keyboard work well with a Mac:
it shows the code of every key you press, remaps keys and turns one key combination into another.
Bindings are saved and restored after a restart.

## Features

- **Keyboard.** A drawn Windows keyboard: remapped keys are highlighted in blue and labeled with their new value,
  keys with combos are marked in purple, and keys you are pressing light up green. Click a key to open the editor.
- **Key Monitor.** For each key press: the HID code (what the keyboard sends), the macOS key code, the character and the keyboard name.
  If the keyboard sent a key that macOS never received, you see it right away.
- **Remaps** (key → key) through the system `hidutil`. Apply them to every keyboard or only to the Windows keyboard,
  so the MacBook's built-in keyboard stays unchanged. Targets include media keys, volume, brightness and Fn.
- **Combos** (shortcut → shortcut), for example `Insert → ⌘V`, `Ctrl+C → ⌘C`, `PrtSc → ⌘⇧4`.
- **Presets** in Settings: swap Win and Alt, Print Screen, Home/End like in Windows, Ctrl shortcuts like in Windows.
- **After restart** the app starts in the background (LaunchAgent), reapplies the bindings and lives in the menu bar.
  Bindings are reapplied whenever a keyboard is connected.
- Export and import of settings as JSON. Settings live in `~/Library/Application Support/KeyBindingApp/config.json`.

## Building

Needs macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./scripts/build-app.sh
open build/KeyBindingApp.app
```

Move `build/KeyBindingApp.app` to Applications and launch it from there, so launch at login points to the right place.
You can also open `Package.swift` in Xcode and run it from there.

If the app was downloaded from GitHub Actions, macOS may refuse to open it. Then run
`xattr -dr com.apple.quarantine /Applications/KeyBindingApp.app` or right-click → Open.

`swift scripts/make-icon.swift` redraws the app icon into `Resources/AppIcon.icns`.

## Permissions

On first launch macOS asks for two permissions (System Settings → Privacy & Security):

| Permission | Why |
|---|---|
| Input Monitoring | To see key codes and which keyboard they came from |
| Accessibility | To replace key combinations (combos) |

Plain remaps through `hidutil` work without either of them.

The app is signed ad hoc, and macOS ties permissions to the signature. After every rebuild the permissions have to be
granted again (remove the old entry and enable the new one). To avoid that, sign with your own certificate:
`SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh`.

## How it works

| File | What it does |
|---|---|
| `Services/HIDMonitor.swift` | Reads keyboards through IOHIDManager and watches for connections |
| `Services/RemapEngine.swift` | Applies remaps with `hidutil property --set '{"UserKeyMapping":[...]}'` |
| `Services/ComboEngine.swift` | CGEventTap: catches a combination and sends another one instead |
| `Services/LaunchAgent.swift` | `~/Library/LaunchAgents/com.keybindingapp.agent.plist`, launched with `--background` |
| `Model/KeyCatalog.swift` | Table of HID codes, macOS key codes and key names |
| `Views/*` | User interface |
| `Debug/Snapshot.swift` | Debug builds only: renders a screen to PNG (`KB_SNAPSHOT=out.png KB_SCREEN=remaps .build/debug/KeyBindingApp`) |

To turn everything off quickly, use the switch in the menu bar. To clear the system remaps by hand:
`hidutil property --set '{"UserKeyMapping":[]}'`.
