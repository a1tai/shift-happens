import AppKit
import SwiftUI

// MARK: - Remap editor

struct RemapEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: KeyRemap
    private let isNew: Bool

    init(remap: KeyRemap) {
        _draft = State(initialValue: remap)
        isNew = !AppState.shared.config.remaps.contains { $0.id == remap.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Remap" : "Remap").font(.title2.bold())

            Form {
                LabeledContent("Key") {
                    KeyField(usage: $draft.from, keys: KeyCatalog.sources) { event in
                        // The key belongs to the keyboard it was pressed on; switch to "all" below if needed.
                        draft.device = event.device
                    }
                }
                LabeledContent("Acts as") {
                    KeyField(usage: $draft.to, keys: KeyCatalog.targets)
                }
                Picker("Keyboard", selection: deviceSelection) {
                    Text("All keyboards (including built-in)").tag(String?.none)
                    DevicePickerItems(devices: deviceOptions)
                }
                Toggle("Enabled", isOn: $draft.enabled)
            }
            .formStyle(.grouped)

            preview

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        state.deleteRemaps([draft.id])
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    state.save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.from == draft.to)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var preview: some View {
        HStack(spacing: 12) {
            KeyBadge(text: KeyCatalog.name(for: draft.from))
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            KeyBadge(text: KeyCatalog.name(for: draft.to), highlighted: true)
            Spacer()
            Text("\(draft.from.hexDescription) → \(draft.to.hexDescription)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var deviceOptions: [DeviceRef] {
        var list = state.keyboardChoices
        if let device = draft.device, !list.contains(where: { $0.matches(device) }) {
            list.append(device) // saved for a keyboard that is unplugged right now
        }
        return list
    }

    private var deviceSelection: Binding<String?> {
        Binding(
            get: { draft.device?.id },
            set: { id in draft.device = deviceOptions.first { $0.id == id } }
        )
    }
}

// MARK: - Combo editor

struct ComboEditor: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ComboBinding
    @State private var sendsMacro: Bool
    private let isNew: Bool

    init(combo: ComboBinding) {
        _draft = State(initialValue: combo)
        _sendsMacro = State(initialValue: combo.isMacro || DebugSnapshot.opensMacroEditor)
        isNew = !AppState.shared.config.combos.contains { $0.id == combo.id }
    }

    /// A sheet sizes itself to its content, so the macro sheet gets an explicit height: most of the
    /// main window's, but never so little that the step list gets cramped, nor taller than the screen.
    private static var macroSheetHeight: CGFloat {
        let window = AppDelegate.shared?.mainWindowHeight ?? 720
        let screen = (NSScreen.main?.visibleFrame.height ?? 900) - 60
        return min(screen, max(640, window * 0.85))
    }

    private var canSave: Bool {
        sendsMacro ? draft.isMacro : draft.trigger != draft.output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Combo" : "Combo").font(.title2.bold())
            if !sendsMacro {
                Text("When you press the first combination, the app sends the second one instead. For example Insert → ⌘V or ⌃C → ⌘C.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Compact rows instead of form groups, so the macro steps get the room.
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("When pressed").gridColumnAlignment(.trailing)
                    ChordEditor(chord: $draft.trigger)
                }
                GridRow {
                    Text("Send")
                    HStack {
                        Picker("Send", selection: $sendsMacro) {
                            Text("Shortcut").tag(false)
                            Text("Macro").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                    }
                }
                if !sendsMacro {
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        ChordEditor(chord: $draft.output)
                    }
                }
                GridRow {
                    Text("Note")
                    HStack(spacing: 14) {
                        TextField("Note", text: $draft.note, prompt: Text("for example “Paste”"))
                            .labelsHidden()
                        Toggle("Enabled", isOn: $draft.enabled)
                    }
                }
            }

            if sendsMacro {
                MacroEditor(combo: $draft)
                    .frame(maxHeight: .infinity)
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear { DebugSnapshot.record("macro steps area height", proxy.size.height) }
                    })
            }

            if !state.accessibilityGranted {
                Label("Combos start working once Accessibility is allowed.", systemImage: "lock")
                    .foregroundStyle(.orange)
            }

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        state.deleteCombos([draft.id])
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.cancelAction(!state.isEditingMacroField)
                Button("Save") {
                    var combo = draft
                    if !sendsMacro { combo.macro = [] }
                    state.save(combo)
                    dismiss()
                    if !state.accessibilityGranted { Permissions.request(.accessibility) }
                }
                .defaultAction(!state.isEditingMacroField)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: sendsMacro ? 780 : 560, height: sendsMacro ? Self.macroSheetHeight : nil)

    }
}

/// Edits a key + modifiers: a key field (click to record, arrow to pick) and the ⌃⌥⇧⌘ toggles.
struct ChordEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var chord: KeyChord
    /// Lists Shift, Control and the like as keys too (macro steps that hold a modifier).
    var allowsModifierKeys = false
    var compact = false
    @State private var recorderID = UUID()

    private var isRecording: Bool { state.activeRecorder == recorderID }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            KeyFieldShell(text: chord.display, isRecording: isRecording, minWidth: compact ? 120 : 160,
                          onClick: { isRecording ? stopRecording() : startRecording() }) {
                KeyMenuItems(keys: allowsModifierKeys ? KeyCatalog.chordKeysWithModifiers : KeyCatalog.chordKeys) { key in
                    if let code = key.macKeyCode { chord.keyCode = code }
                }
            }
            .help(isRecording ? "Press the shortcut. Esc cancels." : "Click to record a shortcut, or pick a key with the arrow")
            if !compact { Spacer(minLength: 8) }
            HStack(spacing: 3) {
                ForEach(ModifierToggle.all) { item in
                    let on = chord.modifiers.contains(item.flag)
                    Button {
                        if on { chord.modifiers.remove(item.flag) } else { chord.modifiers.insert(item.flag) }
                    } label: {
                        Text(item.symbol)
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .frame(width: compact ? 22 : 26, height: compact ? 20 : 24)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    /// Records from raw keyboard input when Input Monitoring is allowed, so shortcuts macOS keeps to itself
    /// (⌘⇧4, ⌘Space) are recorded too; they are switched off while recording. Without Input Monitoring
    /// only key presses that reach this window can be recorded.
    private func startRecording() {
        state.startRecording(recorderID)
        state.chordCaptureHandler = { recorded in
            chord = recorded
            stopRecording()
        }
    }

    private func stopRecording() {
        state.stopRecording(recorderID)
    }
}

struct ModifierToggle: Identifiable {
    let symbol: String
    let name: String
    let flag: ModifierSet

    var id: String { symbol }

    static let all = [
        ModifierToggle(symbol: "⌃", name: "Control", flag: .control),
        ModifierToggle(symbol: "⌥", name: "Option (Alt)", flag: .option),
        ModifierToggle(symbol: "⇧", name: "Shift", flag: .shift),
        ModifierToggle(symbol: "⌘", name: "Command (Win)", flag: .command),
    ]
}

// MARK: - Shared pieces

/// Picker rows for a device choice: keyboards first, then mice. Tags are device IDs.
struct DevicePickerItems: View {
    @EnvironmentObject private var state: AppState
    let devices: [DeviceRef]

    var body: some View {
        let keyboards = devices.filter { !$0.isMouse }
        let mice = devices.filter(\.isMouse)
        if !keyboards.isEmpty {
            Section("Keyboards") {
                ForEach(keyboards) { Text(state.displayName(of: $0)).tag(String?.some($0.id)) }
            }
        }
        if !mice.isEmpty {
            Section("Mice & other devices") {
                ForEach(mice) { device in
                    Label(state.displayName(of: device), systemImage: "computermouse").tag(String?.some(device.id))
                }
            }
        }
    }
}

/// One key, chosen by pressing it (click the field) or from the categorized menu (the arrow).
/// Esc cancels recording; Esc itself can be picked from the menu.
struct KeyField: View {
    @EnvironmentObject private var state: AppState
    @Binding var usage: HIDUsage
    let keys: [KeyDef]
    /// Called after a recorded press, e.g. to note which keyboard it came from.
    var onRecord: (HIDKeyEvent) -> Void = { _ in }
    @State private var recorderID = UUID()

    private var isRecording: Bool { state.activeRecorder == recorderID }

    var body: some View {
        KeyFieldShell(text: KeyCatalog.name(for: usage), isRecording: isRecording, minWidth: 200,
                      onClick: toggleRecording) {
            KeyMenuItems(keys: keys) { usage = $0.hid }
        }
        .disabled(!state.inputMonitoringGranted && !isRecording && keys.isEmpty)
        .help(state.inputMonitoringGranted
              ? (isRecording ? "Press a key. Esc cancels." : "Click and press a key, or pick one with the arrow")
              : "Pick a key with the arrow. Recording a key press needs Input Monitoring access.")
        .onDisappear { state.stopRecording(recorderID) }
    }

    private func toggleRecording() {
        if isRecording {
            state.stopRecording(recorderID)
        } else if state.inputMonitoringGranted {
            // Starting this recorder stops any other one.
            state.startRecording(recorderID)
            state.captureHandler = { event in
                usage = event.usage
                onRecord(event)
                state.stopRecording(recorderID)
            }
        }
    }
}

/// The look shared by key fields: a rounded field showing the key that records on click,
/// with an arrow at its trailing edge for the key menu.
struct KeyFieldShell<MenuContent: View>: View {
    let text: String
    let isRecording: Bool
    var minWidth: CGFloat = 160
    let onClick: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClick) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                    }
                    Text(isRecording ? "Press keys…" : text)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(isRecording ? Color.accentColor : .primary)
                        .lineLimit(1)
                }
                .frame(minWidth: minWidth - 28, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().frame(height: 16)
            Menu(content: menu) {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .help("Pick a key from the list")
        }
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isRecording ? 2 : 1))
        .fixedSize()
    }
}

/// Menu entries for every key, grouped by category.
struct KeyMenuItems: View {
    let keys: [KeyDef]
    let pick: (KeyDef) -> Void

    var body: some View {
        ForEach(KeyDef.Category.allCases, id: \.self) { category in
            let group = keys.filter { $0.category == category }
            if !group.isEmpty {
                Menu(category.rawValue) {
                    ForEach(group) { key in
                        Button(key.name) { pick(key) }
                    }
                }
            }
        }
    }
}

struct KeyBadge: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(highlighted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.15))
            )
    }
}

extension View {
    /// Makes this the Return-key button only while `enabled`.
    @ViewBuilder
    func defaultAction(_ enabled: Bool) -> some View {
        if enabled { keyboardShortcut(.defaultAction) } else { self }
    }
}

extension View {
    /// Makes this the Esc-key button only while `enabled`.
    @ViewBuilder
    func cancelAction(_ enabled: Bool) -> some View {
        if enabled { keyboardShortcut(.cancelAction) } else { self }
    }
}
