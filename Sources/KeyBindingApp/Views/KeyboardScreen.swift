import SwiftUI

/// The drawn Windows keyboard: shows what each key does now and lets you click a key to change it.
struct KeyboardScreen: View {
    @EnvironmentObject private var state: AppState
    /// nil = remaps for every keyboard.
    @State private var deviceID: String?
    @State private var editing: KeyRemap?
    @State private var hovered: UInt32?

    private var device: DeviceRef? { state.keyboardChoices.first { $0.id == deviceID } }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                header
                KeyboardGrid { unit in
                    ForEach(KeyboardLayout.keys) { cap in
                        KeyCapView(
                            cap: cap,
                            unit: unit,
                            remap: remap(for: cap),
                            comboCount: comboCount(for: cap),
                            isPressed: state.pressedKeys.contains(cap.hid.hidutilValue),
                            isHovered: hovered == cap.usage
                        )
                        .onHover { hovered = $0 ? cap.usage : (hovered == cap.usage ? nil : hovered) }
                        .onTapGesture { edit(cap) }
                        .help(tooltip(for: cap))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
                legend
                detail
            }
            .padding(24)
        }
        .onAppear {
            state.setKeyboardScreenOpen(true)
            if DebugSnapshot.opensEditor, let esc = KeyboardLayout.keys.first { edit(esc) }
        }
        .onDisappear { state.setKeyboardScreenOpen(false) }
        .sheet(item: $editing) { remap in
            RemapEditor(remap: remap)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard").font(.largeTitle.bold())
                Text("Click a key to make it act as another key. Keys you press light up.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Keyboard", selection: $deviceID) {
                Text("All keyboards").tag(String?.none)
                if !state.keyboardChoices.isEmpty { Divider() }
                DevicePickerItems(devices: state.keyboardChoices)
            }
            .frame(maxWidth: 280)
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            LegendItem(color: .accentColor, text: "Remapped")
            LegendItem(color: .purple, text: "Triggers a combo")
            LegendItem(color: .green, text: "Pressed now")
            Spacer(minLength: 12)
            Text(counted(state.config.remaps.count, "remap") + " · " + counted(state.config.combos.count, "combo"))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
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
                Text("Hover over a key to see its bindings.")
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

/// Fills the available width with the keyboard and places each key cap by its position in key units.
/// Keys never get smaller than `minUnit`; below that the keyboard scrolls horizontally instead.
private struct KeyboardGrid<Content: View>: View {
    static var minUnit: CGFloat { 24 }
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var unit: CGFloat = 40

    var body: some View {
        ScrollView(.horizontal) {
            KeyCapLayout(unit: unit) { content(unit) }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { update(proxy.size.width) }
                    .onChange(of: proxy.size.width) { update($0) }
            })
    }

    private func update(_ width: CGFloat) {
        let fitted = max(Self.minUnit, (width / KeyboardLayout.width).rounded(.down))
        if fitted != unit { unit = fitted }
    }
}

/// Places subviews in the order of `KeyboardLayout.keys`, with a small gap between caps.
private struct KeyCapLayout: Layout {
    let unit: CGFloat
    private let gap: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: KeyboardLayout.width * unit, height: KeyboardLayout.height * unit)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (cap, subview) in zip(KeyboardLayout.keys, subviews) {
            subview.place(
                at: CGPoint(x: bounds.minX + cap.x * unit + gap / 2, y: bounds.minY + cap.y * unit + gap / 2),
                proposal: ProposedViewSize(width: cap.width * unit - gap, height: cap.height * unit - gap)
            )
        }
    }
}

private struct KeyCapView: View {
    let cap: KeyCap
    let unit: CGFloat
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

    private var fontSize: CGFloat { max(9, unit * 0.28) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous)
                .fill(tint.map { $0.opacity(isPressed ? 0.55 : 0.22) } ?? Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 0.5, y: 1)
            RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor : (tint ?? Color.primary.opacity(0.12)),
                              lineWidth: isHovered ? 2 : 1)
            VStack(spacing: unit * 0.04) {
                Text(KeyCatalog.label(for: cap.hid))
                    .font(.system(size: remap == nil ? fontSize : fontSize * 0.85, weight: .medium))
                    .strikethrough(remap?.enabled == true, color: .secondary)
                    .foregroundStyle(remap?.enabled == true ? .secondary : .primary)
                if let remap {
                    Text(KeyCatalog.label(for: remap.to))
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(remap.enabled ? Color.accentColor : .secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .padding(.horizontal, 3)
            if comboCount > 0 {
                Image(systemName: "command")
                    .font(.system(size: fontSize * 0.7, weight: .bold))
                    .foregroundStyle(.purple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(unit * 0.08)
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
