# Changelog

## Unreleased

- Combos can do an Action: Paste as Plain Text (works in any app, puts the clipboard back afterwards) or
  Run Shortcut (a shortcut from the Shortcuts app; if it fails, the reason shows in the sidebar).
- More actions: Change Case of the selected text (UPPERCASE, lowercase, Title Case) and window actions
  (Maximize, Left Half, Right Half, Restore) for the front window, on whichever screen it is.

## 1.0.2 — 2026-10-22

- Releases are signed with the same certificate every time, so macOS keeps the Input Monitoring and
  Accessibility permissions when you update. Coming from 1.0.0 or 1.0.1, allow them once more; after that
  they stay.
- No more code for moving settings over from the pre-release builds; the old name is gone everywhere.

## 1.0.1 — 2026-10-22

- The program inside the app is now called ShiftHappens.
- The app reports its version as 1.0.1; the release zip is named `Shift-Happens.zip`.
- Release notes come from this changelog.

## 1.0.0 — 2026-10-22

First public version.

- Keyboard screen with a drawn Mac or Windows keyboard showing remaps, combos and pressed keys.
- Key Monitor: the last key press with its HID code, macOS key code, character and keyboard; a special key that sends
  several keys shows as one press with the full chord. No history.
- Remaps (key → key) through `hidutil`, for every keyboard or one keyboard; restored after restart.
- Combos: a key, shortcut or extra mouse button sends another shortcut or plays a macro
  (key down/up events, delays, typed text), recorded from the keyboard or edited by hand.
- Combos can open an app or bring it to the front; macros have an Open App step.
- Layout Fixer (adapted from Perekluk): retypes the last word or the selection in the other layout.
- Input language in the menu bar icon, layout switching and Emoji & Symbols from its menu.
- Presets for Windows keyboards and for mouse Back/Forward in Safari and Finder.
- Launch at login, settings export/import, welcome sheet for the two permissions.
