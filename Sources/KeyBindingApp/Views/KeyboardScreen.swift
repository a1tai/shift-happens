import SwiftUI

/// The drawn Windows keyboard: shows what each key does now and lets you click a key to change it.
struct KeyboardScreen: View {
    @EnvironmentObject private var state: AppState
    /// nil = remaps for every keyboard.
    @State private var deviceID: String?
    @State private var editing: KeyRemap?
    @State private var hovered: UInt32?

    private var device: DeviceRef? { state.devices.first { $0.id == deviceID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            GeometryReader { proxy in
                let unit = min(proxy.size.width / KeyboardLayout.width, proxy.size.height / KeyboardLayout.height)
                ZStack(alignment: .topLeading) {
                    ForEach(KeyboardLayout.keys) { cap in
                        KeyCapView(
                            cap: cap,
                            remap: remap(for: cap),
                            comboCount: comboCount(for: cap),
                            isPressed: state.pressedKeys.contains(cap.hid.hidutilValue),
                            isHovered: hovered == cap.usage
                        )
                        .frame(width: cap.width * unit - 4, height: cap.height * unit - 4)
                        .offset(x: cap.x * unit + 2, y: cap.y * unit + 2)
                        .onHover { hovered = $0 ? cap.usage : (hovered == cap.usage ? nil : hovered) }
                        .onTapGesture { edit(cap) }
                        .help(tooltip(for: cap))
                    }
                }
                .frame(width: KeyboardLayout.width * unit, height: KeyboardLayout.height * unit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
            .aspectRatio(KeyboardLayout.width / KeyboardLayout.height, contentMode: .fit)
            legend
            detail
            Spacer(minLength: 0)
        }
        .padding(24)
        .sheet(item: $editing) { remap in
            RemapEditor(remap: remap)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Клавиатура").font(.largeTitle.bold())
                Text("Нажмите на клавишу, чтобы назначить ей другую. Нажатия на клавиатуре подсвечиваются.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Клавиатура", selection: $deviceID) {
                Text("Все клавиатуры").tag(String?.none)
                if !state.devices.isEmpty { Divider() }
                ForEach(state.devices) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
            }
            .frame(maxWidth: 280)
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            LegendItem(color: .accentColor, text: "Переназначена")
            LegendItem(color: .purple, text: "Запускает комбинацию")
            LegendItem(color: .green, text: "Нажата сейчас")
            Spacer()
            Text("\(state.config.remaps.count) переназначений · \(state.config.combos.count) комбинаций")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var detail: some View {
        if let usage = hovered, let cap = KeyboardLayout.keys.first(where: { $0.usage == usage }) {
            GroupBox {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(KeyCatalog.name(for: cap.hid)).font(.headline)
                        Text("HID \(cap.hid.hexDescription)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let remap = remap(for: cap) {
                        Label("→ \(KeyCatalog.name(for: remap.to))", systemImage: "arrow.right.circle.fill")
                            .foregroundStyle(remap.enabled ? Color.accentColor : .secondary)
                    }
                    ForEach(combos(for: cap)) { combo in
                        Label("\(combo.trigger.display) → \(combo.output.display)", systemImage: "command.circle.fill")
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            GroupBox {
                Text("Наведите курсор на клавишу, чтобы увидеть её привязки.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Data

    private func remap(for cap: KeyCap) -> KeyRemap? {
        let candidates = state.config.remaps.filter { $0.from == cap.hid }
        if let device {
            return candidates.first { $0.device?.matches(device) == true } ?? candidates.first { $0.device == nil }
        }
        return candidates.first { $0.device == nil } ?? candidates.first
    }

    private func combos(for cap: KeyCap) -> [ComboBinding] {
        // Combos are matched by the key code macOS produces, which a remap may change.
        let effective = remap(for: cap).flatMap { $0.enabled ? $0.to : nil } ?? cap.hid
        guard let code = KeyCatalog.key(for: effective)?.macKeyCode else { return [] }
        return state.config.combos.filter { $0.trigger.keyCode == code }
    }

    private func comboCount(for cap: KeyCap) -> Int { combos(for: cap).count }

    private func tooltip(for cap: KeyCap) -> String {
        var text = KeyCatalog.name(for: cap.hid)
        if let remap = remap(for: cap) { text += " → " + KeyCatalog.name(for: remap.to) }
        return text
    }

    private func edit(_ cap: KeyCap) {
        editing = remap(for: cap) ?? KeyRemap(from: cap.hid, to: cap.hid, device: device)
    }
}

private struct KeyCapView: View {
    let cap: KeyCap
    let remap: KeyRemap?
    let comboCount: Int
    let isPressed: Bool
    let isHovered: Bool

    private var tint: Color? {
        if isPressed { return .green }
        if let remap, remap.enabled { return .accentColor }
        if comboCount > 0 { return .purple }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.map { $0.opacity(isPressed ? 0.55 : 0.22) } ?? Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor : (tint ?? Color.primary.opacity(0.12)),
                              lineWidth: isHovered ? 2 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(KeyCatalog.label(for: cap.hid))
                    .font(.system(size: 11, weight: .medium))
                    .strikethrough(remap?.enabled == true, color: .secondary)
                    .foregroundStyle(remap?.enabled == true ? .secondary : .primary)
                Spacer(minLength: 0)
                if let remap {
                    Text("→ " + KeyCatalog.label(for: remap.to))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(remap.enabled ? Color.accentColor : .secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(5)
            if comboCount > 0 {
                Image(systemName: "command")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}

struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color))
                .frame(width: 14, height: 14)
            Text(text)
        }
    }
}
