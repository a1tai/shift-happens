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
                    HStack {
                        KeyPicker(selection: $draft.from, keys: KeyCatalog.sources)
                        CaptureButton { event in
                            // The key belongs to the keyboard it was pressed on; switch to "all" below if needed.
                            draft.from = event.usage
                            draft.device = event.device
                        }
                    }
                }
                LabeledContent("Acts as") {
                    HStack {
                        KeyPicker(selection: $draft.to, keys: KeyCatalog.targets)
                        CaptureButton { draft.to = $0.usage }
                    }
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
    private let isNew: Bool

    init(combo: ComboBinding) {
        _draft = State(initialValue: combo)
        isNew = !AppState.shared.config.combos.contains { $0.id == combo.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Combo" : "Combo").font(.title2.bold())
            Text("When you press the first combination, the app sends the second one instead. For example Insert → ⌘V or ⌃C → ⌘C.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Section("When pressed") { ChordEditor(chord: $draft.trigger) }
                Section("Send") { ChordEditor(chord: $draft.output) }
                Section {
                    TextField("Note", text: $draft.note, prompt: Text("for example “Paste”"))
                    Toggle("Enabled", isOn: $draft.enabled)
                }
            }
            .formStyle(.grouped)

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
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    state.save(draft)
                    dismiss()
                    if !state.accessibilityGranted { Permissions.request(.accessibility) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trigger == draft.output)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

/// Edits a key + modifiers, either by recording a press or by picking from lists
/// (useful for shortcuts the system grabs before the app sees them, like ⌘Tab).
struct ChordEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var chord: KeyChord
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press keys…" : chord.display)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .frame(minWidth: 130)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .help(isRecording ? "Press the shortcut, or click to cancel" : "Click, then press a key combination")

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(ModifierToggle.all) { item in
                    let on = chord.modifiers.contains(item.flag)
                    Button {
                        if on { chord.modifiers.remove(item.flag) } else { chord.modifiers.insert(item.flag) }
                    } label: {
                        Text(item.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 26, height: 24)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
            Picker("", selection: $chord.keyCode) {
                ForEach(KeyDef.Category.allCases, id: \.self) { category in
                    let keys = KeyCatalog.chordKeys.filter { $0.category == category }
                    if !keys.isEmpty {
                        Section(category.rawValue) {
                            ForEach(keys) { key in
                                Text(key.name).tag(key.macKeyCode ?? 0)
                            }
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 140)
        }
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }

    /// Records from raw keyboard input when Input Monitoring is allowed, so shortcuts macOS keeps to itself
    /// (⌘⇧4, ⌘Space) are recorded too; while recording, those system shortcuts are switched off.
    /// Without Input Monitoring only key presses that reach this window can be recorded.
    private func startRecording() {
        isRecording = true
        state.combos.isPaused = true
        state.swallowLocalKeys += 1
        SystemShortcuts.disable()
        if state.inputMonitoringGranted {
            state.chordCaptureHandler = { recorded in
                chord = recorded
                stopRecording()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if !state.inputMonitoringGranted {
                chord = KeyChord(keyCode: event.keyCode,
                                 modifiers: ModifierSet(nsFlags: event.modifierFlags).subtracting(.function))
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        state.chordCaptureHandler = nil
        state.swallowLocalKeys -= 1
        state.combos.isPaused = false
        SystemShortcuts.restore()
    }
}

private struct ModifierToggle: Identifiable {
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

/// A menu of keys grouped by category.
struct KeyPicker: View {
    @Binding var selection: HIDUsage
    let keys: [KeyDef]

    var body: some View {
        Picker("", selection: $selection) {
            if KeyCatalog.key(for: selection) == nil {
                Text(KeyCatalog.name(for: selection)).tag(selection)
            }
            ForEach(KeyDef.Category.allCases, id: \.self) { category in
                let group = keys.filter { $0.category == category }
                if !group.isEmpty {
                    Section(category.rawValue) {
                        ForEach(group) { key in
                            Text(key.name).tag(key.hid)
                        }
                    }
                }
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// "Press a key" button: the next physical key press (from any keyboard) is passed to `onCapture`.
struct CaptureButton: View {
    @EnvironmentObject private var state: AppState
    let onCapture: (HIDKeyEvent) -> Void
    @State private var waiting = false

    var body: some View {
        Button(waiting ? "Press a key…" : "Record") {
            if waiting {
                cancel()
            } else {
                waiting = true
                state.swallowLocalKeys += 1
                state.captureHandler = { event in
                    onCapture(event)
                    finish()
                }
            }
        }
        .disabled(!state.inputMonitoringGranted)
        .help(state.inputMonitoringGranted ? "Click, then press a key on the keyboard" : "Needs Input Monitoring access")
        .onDisappear(perform: cancel)
    }

    private func finish() {
        guard waiting else { return }
        waiting = false
        state.swallowLocalKeys -= 1
    }

    private func cancel() {
        if waiting { state.captureHandler = nil }
        finish()
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
