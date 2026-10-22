# Changelog

## 1.0.0 — unreleased

First public version.

- Keyboard screen with a drawn Mac or Windows keyboard showing remaps, combos and pressed keys.
- Key Monitor: the last key press with its HID code, macOS key code, character and keyboard. No history.
- Remaps (key → key) through `hidutil`, for every keyboard or one keyboard; restored after restart.
- Combos: a key, shortcut or extra mouse button sends another shortcut or plays a macro
  (key down/up events, delays, typed text), recorded from the keyboard or edited by hand.
- Layout Fixer (adapted from Perekluk): retypes the last word or the selection in the other layout.
- Input language in the menu bar icon, layout switching and Emoji & Symbols from its menu.
- Presets for Windows keyboards and for mouse Back/Forward in Safari and Finder.
- Launch at login, settings export/import, welcome sheet for the two permissions.
