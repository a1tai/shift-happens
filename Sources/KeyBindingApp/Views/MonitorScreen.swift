import SwiftUI

/// Live view of key presses: the raw code from the keyboard and what macOS turned it into.
/// Presses exist only in memory while this screen is on screen; nothing is saved.
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
                Label("Nothing is saved. History is cleared when you leave this screen.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let last = state.log.first {
                LastKeyCard(entry: last, onRemap: { remap(last) }, onCombo: { combo(last) })
            } else {
                GroupBox {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Waiting for a key press…").font(.title3).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                }
            }

            HStack {
                Toggle("Keep history", isOn: $state.keepsKeyHistory)
                    .toggleStyle(.switch)
                    .help("List the last \(50) presses instead of only the last one. Kept in memory while you look at this screen.")
                Spacer()
                if state.keepsKeyHistory {
                    Button("Clear", action: state.clearLog).disabled(state.log.isEmpty)
                }
            }
            if state.keepsKeyHistory {
                historyTable
            } else {
                Spacer(minLength: 0)
            }
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

    private var historyTable: some View {
        Table(state.log) {
            TableColumn("Time") { entry in
                Text(entry.time, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Key") { entry in
                Text(entry.keyName)
            }
            TableColumn("HID code") { entry in
                Text(entry.hid.map { $0.usage.hexDescription } ?? "—").font(.body.monospaced())
            }
            .width(110)
            TableColumn("macOS code") { entry in
                if let code = entry.macKeyCode {
                    Text("\(code) (0x\(String(code, radix: 16, uppercase: true)))").font(.body.monospaced())
                } else {
                    Text(entry.macIgnoredIt ? "not received" : "—")
                        .foregroundStyle(entry.macIgnoredIt ? Color.orange : .secondary)
                }
            }
            .width(110)
            TableColumn("Character") { entry in
                Text(entry.symbol).font(.body.monospaced())
            }
            .width(70)
            TableColumn("Keyboard") { entry in
                Text(entry.hid?.device.name ?? "—").foregroundStyle(.secondary)
            }
        }
    }

    private func remap(_ entry: KeyLogEntry) {
        guard let hid = entry.hid else { return }
        let existing = state.config.remaps.first { $0.from == hid.usage && $0.device?.matches(hid.device) == true }
        editingRemap = existing ?? KeyRemap(from: hid.usage, to: hid.usage, device: hid.device)
    }

    private func combo(_ entry: KeyLogEntry) {
        let code = entry.macKeyCode ?? entry.hid.flatMap { KeyCatalog.key(for: $0.usage)?.macKeyCode } ?? 0
        let chord = KeyChord(keyCode: code, modifiers: entry.macModifiers)
        editingCombo = ComboBinding(trigger: chord, output: chord)
    }
}

extension KeyLogEntry {
    var keyName: String {
        if let hid { return KeyCatalog.name(for: hid.usage) }
        if let code = macKeyCode { return KeyCatalog.key(forMacKeyCode: code)?.name ?? "Code \(code)" }
        return "—"
    }

    /// The printed character, with control characters made visible.
    var symbol: String {
        guard let characters, let scalar = characters.unicodeScalars.first else { return "—" }
        switch scalar.value {
        case 0x0D, 0x03: return "↩"
        case 0x09: return "⇥"
        case 0x1B: return "⎋"
        case 0x7F, 0x08: return "⌫"
        case 0x20: return "␣"
        case 0x00...0x1F, 0xF700...0xF8FF: return "—"
        default: return characters
        }
    }
}

private struct LastKeyCard: View {
    let entry: KeyLogEntry
    let onRemap: () -> Void
    let onCombo: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 28) {
                Text(entry.symbol == "—" ? KeyCatalog.label(for: entry.hid?.usage ?? HIDUsage(page: 0, usage: 0)) : entry.symbol)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .frame(minWidth: 110, minHeight: 110)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.15)))

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Key").foregroundStyle(.secondary)
                        Text(entry.keyName).font(.headline)
                    }
                    GridRow {
                        Text("HID code").foregroundStyle(.secondary)
                        Text(entry.hid.map { "\($0.usage.hexDescription)  (page 0x\(String($0.usage.page, radix: 16, uppercase: true)), usage 0x\(String($0.usage.usage, radix: 16, uppercase: true)))" } ?? "no Input Monitoring access")
                            .font(.body.monospaced())
                    }
                    GridRow {
                        Text("macOS code").foregroundStyle(.secondary)
                        if let code = entry.macKeyCode {
                            Text("\(code)  \(entry.macModifiers.symbols)").font(.body.monospaced())
                        } else if entry.macIgnoredIt {
                            Label("macOS didn't receive this key. You can remap it.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else {
                            Text("—")
                        }
                    }
                    GridRow {
                        Text("Keyboard").foregroundStyle(.secondary)
                        Text(entry.hid.map { "\($0.device.name)  (\(String(format: "%04X:%04X", $0.device.vendorID, $0.device.productID)))" } ?? "—")
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Remap…", action: onRemap)
                        .buttonStyle(.borderedProminent)
                        .disabled(entry.hid == nil)
                    Button("Create Combo…", action: onCombo)
                }
            }
            .padding(8)
        }
    }
}
