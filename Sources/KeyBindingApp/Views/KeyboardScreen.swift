import SwiftUI

/// The drawn keyboard, Mac or Windows: shows what each key does now and lets you click a key to change it.
struct KeyboardScreen: View {
    @EnvironmentObject private var state: AppState
    /// nil = remaps for every keyboard.
    @State private var deviceID: String?
    @State private var editing: KeyRemap?
    @State private var hovered: UInt64?
    @AppStorage("keyboardStyle") private var style: KeyboardLayout.Style = .mac

    private var layout: KeyboardLayout { style.layout }

    private var device: DeviceRef? { state.keyboardChoices.first { $0.id == deviceID } }

    var body: some View {
        // No scrolling: the keyboard gets as large as the space under the header allows,
        // with the legend and the key details right below it.
        VStack(alignment: .leading, spacing: 16) {
            header
            GeometryReader { proxy in
                let reserved = Self.legendHeight + Self.detailHeight + 2 * Self.spacing
                VStack(spacing: Self.spacing) {
                    keyboard(fitting: CGSize(width: proxy.size.width, height: proxy.size.height - reserved))
                    legend.frame(height: Self.legendHeight)
                    detail.frame(height: Self.detailHeight)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .padding(24)
        .onAppear {
            state.setKeyboardScreenOpen(true)
            if DebugSnapshot.opensEditor, let esc = layout.keys.first { edit(esc) }
        }
        .onDisappear { state.setKeyboardScreenOpen(false) }
        .sheet(item: $editing) { remap in
            RemapEditor(remap: remap)
        }
    }

    private static let spacing: CGFloat = 16
    private static let legendHeight: CGFloat = 20
    private static let detailHeight: CGFloat = 60

    private func keyboard(fitting size: CGSize) -> some View {
        KeyboardGrid(layout: layout, size: size) { unit in
            ForEach(layout.keys) { cap in
                KeyCapView(
                    cap: cap,
                    style: style,
                    unit: unit,
                    remap: remap(for: cap),
                    comboCount: comboCount(for: cap),
                    isPressed: state.pressedKeys.contains(cap.hid.hidutilValue),
                    isHovered: hovered == cap.id
                )
                .onHover { hovered = $0 ? cap.id : (hovered == cap.id ? nil : hovered) }
                .onTapGesture { edit(cap) }
                .help(tooltip(for: cap))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: style)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard").font(.largeTitle.bold())
                Text("Click a key to make it act as another key. Keys you press light up.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Layout", selection: $style) {
                ForEach(KeyboardLayout.Style.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Draw a Mac or a Windows keyboard. Both show the same remaps.")
            Picker("Keyboard", selection: $deviceID) {
                Text("All keyboards").tag(String?.none)
                if !state.keyboardChoices.isEmpty { Divider() }
                DevicePickerItems(devices: state.keyboardChoices)
            }
            .frame(maxWidth: 260)
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
        if let id = hovered, let cap = layout.keys.first(where: { $0.id == id }) {
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
                        Label("\(combo.trigger.display) → \(combo.outputSummary)", systemImage: "command.circle.fill")
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            }
        } else {
            GroupBox {
                // Same height as the key details, so hovering never resizes the keyboard.
                Text("Hover over a key to see its bindings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
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
/// Draws the keyboard as large as `size` allows, in both directions, inside a card that hugs it.
/// Never scrolls: in a small window the keys get smaller instead.
private struct KeyboardGrid<Content: View>: View {
    /// The small Mac keyboard would get huge keys in a big window.
    static var maxUnit: CGFloat { 64 }
    static var cardPadding: CGFloat { 16 }
    let layout: KeyboardLayout
    let size: CGSize
    @ViewBuilder let content: (CGFloat) -> Content

    private var unit: CGFloat {
        let inset = Self.cardPadding * 2
        let fit = min((size.width - inset) / layout.width, (size.height - inset) / layout.height)
        return max(1, min(Self.maxUnit, fit.rounded(.down)))
    }

    var body: some View {
        let unit = self.unit
        let _ = DebugSnapshot.recordKeyboardFit(
            drawn: CGSize(width: layout.width * unit, height: layout.height * unit),
            available: CGSize(width: size.width - Self.cardPadding * 2, height: size.height - Self.cardPadding * 2))
        KeyCapLayout(layout: layout, unit: unit) { content(unit) }
            .padding(Self.cardPadding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// Places subviews in the order of the layout's keys, with a gap between caps that scales with them.
private struct KeyCapLayout: Layout {
    let layout: KeyboardLayout
    let unit: CGFloat
    private var gap: CGFloat { (unit * 0.08).rounded() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: layout.width * unit, height: layout.height * unit)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (cap, subview) in zip(layout.keys, subviews) {
            subview.place(
                at: CGPoint(x: bounds.minX + cap.x * unit + gap / 2, y: bounds.minY + cap.y * unit + gap / 2),
                proposal: ProposedViewSize(width: cap.width * unit - gap, height: cap.height * unit - gap)
            )
        }
    }
}

private struct KeyCapView: View {
    let cap: KeyCap
    let style: KeyboardLayout.Style
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

    /// The cap's own text: one line, or a glyph above a word ("⌘" / "command").
    private var lines: [String] { (cap.label ?? KeyCatalog.label(for: cap.hid)).components(separatedBy: "\n") }

    private func label(for usage: HIDUsage) -> String {
        (style == .mac ? KeyboardLayout.macLabel(for: usage) : nil) ?? KeyCatalog.label(for: usage)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous)
                .fill(tint.map { $0.opacity(isPressed ? 0.55 : 0.22) } ?? Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 0.5, y: 1)
            RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor : (tint ?? Color.primary.opacity(0.12)),
                              lineWidth: isHovered ? 2 : 1)
            VStack(spacing: unit * 0.04) {
                if let remap {
                    Text(lines.joined(separator: " "))
                        .font(.system(size: fontSize * 0.7, weight: .medium))
                        .strikethrough(remap.enabled, color: .secondary)
                        .foregroundStyle(remap.enabled ? .secondary : .primary)
                    Text(label(for: remap.to))
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundStyle(remap.enabled ? Color.accentColor : .secondary)
                } else {
                    Text(lines[0])
                        .font(.system(size: lines.count > 1 ? fontSize * 0.9 : fontSize, weight: .medium))
                    if lines.count > 1 {
                        Text(lines[1])
                            .font(.system(size: fontSize * 0.55, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
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
