import SwiftUI

/// Live view of key presses: the raw code from the keyboard and what macOS turned it into.
/// Only the last press exists, in memory, while this screen is on screen; nothing is saved.
struct MonitorScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var editingRemap: KeyRemap?
    @State private var editingCombo: ComboBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Key Monitor").font(.largeTitle.bold())
                Text("Press any key on the keyboard. While this screen is open, key presses don't reach other fields in the app.")
                    .foregroundStyle(.secondary)
                Label("Only the last press is shown — all keys the keyboard sent for it. Nothing is saved, and it is cleared when you leave this screen.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let last = state.lastGesture {
                LastKeyCard(gesture: last, onRemap: { remap(last) }, onCombo: { combo(last) })
            } else {
                GroupBox {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Waiting for a key press…").font(.title3).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear {
            state.swallowLocalKeys += 1
            state.setMonitorScreenOpen(true)
        }
        .onDisappear {
            state.swallowLocalKeys -= 1
            state.setMonitorScreenOpen(false)
        }
        .sheet(item: $editingRemap) { RemapEditor(remap: $0) }
        .sheet(item: $editingCombo) { ComboEditor(combo: $0) }
    }

    private func remap(_ gesture: KeyGesture) {
        guard let usage = gesture.mainKey, let device = gesture.device else { return }
        let existing = state.config.remaps.first { $0.from == usage && $0.device?.matches(device) == true }
        editingRemap = existing ?? KeyRemap(from: usage, to: usage, device: device)
    }

    private func combo(_ gesture: KeyGesture) {
        let chord = gesture.chord ?? KeyChord(keyCode: 0, modifiers: [])
        editingCombo = ComboBinding(trigger: chord, output: chord)
    }
}

extension KeyGesture {
    var keyName: String {
        if let main = mainKey { return KeyCatalog.name(for: main) }
        if let code = macKeys.first?.keyCode { return KeyCatalog.key(forMacKeyCode: code)?.name ?? "Code \(code)" }
        return "—"
    }

    /// The big label: the whole chord, or the printed character of a single key.
    var symbol: String {
        if isChord { return chordDisplay }
        if let characters = macKeys.last?.characters, let shown = Self.visible(characters) { return shown }
        if let main = mainKey { return Self.label(main) }
        return "—"
    }

    /// The printed character, with control characters made visible; nil when there's nothing to print.
    static func visible(_ characters: String) -> String? {
        guard let scalar = characters.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x0D, 0x03: return "↩"
        case 0x09: return "⇥"
        case 0x1B: return "⎋"
        case 0x7F, 0x08: return "⌫"
        case 0x20: return "␣"
        case 0x00...0x1F, 0xF700...0xF8FF: return nil
        default: return characters
        }
    }
}

private extension HIDUsage {
    var pageUsage: String { String(format: "%02X:%02X", page, usage) }
}

private struct LastKeyCard: View {
    let gesture: KeyGesture
    let onRemap: () -> Void
    let onCombo: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 28) {
                Text(gesture.symbol)
                    .font(.system(size: gesture.isChord ? 30 : 44, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 110, maxWidth: 220, minHeight: 110)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.15)))

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text(gesture.isChord ? "Keys" : "Key").foregroundStyle(.secondary)
                        Text(gesture.isChord ? "\(gesture.chordDisplay)  (one press, \(gesture.keys.count) keys)" : gesture.keyName)
                            .font(.headline)
                    }
                    GridRow {
                        Text("HID codes").foregroundStyle(.secondary)
                        hidEvents
                    }
                    GridRow {
                        Text("macOS").foregroundStyle(.secondary)
                        macOutput
                    }
                    GridRow {
                        Text("Keyboard").foregroundStyle(.secondary)
                        Text(devices)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Remap…", action: onRemap)
                        .buttonStyle(.borderedProminent)
                        .disabled(gesture.mainKey.map { !HIDPage.isKeyPage($0.page) } ?? true)
                    Button("Create Combo…", action: onCombo)
                        .disabled(gesture.chord == nil)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder private var hidEvents: some View {
        if gesture.events.isEmpty {
            Text("no Input Monitoring access")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(gesture.events.enumerated()), id: \.offset) { _, event in
                    let ms = Int((event.time.timeIntervalSince(gesture.start) * 1000).rounded())
                    Text("\(event.isDown ? "↓" : "↑") \(event.usage.pageUsage)  \(KeyCatalog.name(for: event.usage))  +\(ms) ms")
                        .font(.body.monospaced())
                        .foregroundStyle(event.isDown ? .primary : .secondary)
                }
                if gesture.isHeld {
                    Text("holding…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var macOutput: some View {
        if !gesture.macKeys.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(gesture.macKeys.enumerated()), id: \.offset) { _, key in
                    let chord = KeyChord(keyCode: key.keyCode, modifiers: key.modifiers.subtracting(.function))
                    Text("\(chord.display)   code \(key.keyCode)").font(.body.monospaced())
                }
            }
        } else if gesture.macIgnoredIt() {
            Label("macOS didn't receive this key. You can remap it.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if gesture.macSawModifiers, !gesture.isHeld {
            Text("only modifiers \(gesture.macModifiers.symbols) — the key went to a system shortcut or was ignored")
                .foregroundStyle(.secondary)
        } else {
            Text("—")
        }
    }

    private var devices: String {
        var seen = Set<String>()
        let list = gesture.events.map(\.device).filter { seen.insert($0.id).inserted }
        guard !list.isEmpty else { return "—" }
        return list.map { "\($0.name)  (\(String(format: "%04X:%04X", $0.vendorID, $0.productID)))" }.joined(separator: ", ")
    }
}
