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
            Text(isNew ? "Новое переназначение" : "Переназначение").font(.title2.bold())

            Form {
                LabeledContent("Клавиша") {
                    HStack {
                        KeyPicker(selection: $draft.from, keys: KeyCatalog.sources)
                        CaptureButton { event in
                            // The key belongs to the keyboard it was pressed on; switch to "all" below if needed.
                            draft.from = event.usage
                            draft.device = event.device
                        }
                    }
                }
                LabeledContent("Работает как") {
                    HStack {
                        KeyPicker(selection: $draft.to, keys: KeyCatalog.targets)
                        CaptureButton { draft.to = $0.usage }
                    }
                }
                Picker("Для клавиатуры", selection: deviceSelection) {
                    Text("Все клавиатуры (и встроенная)").tag(String?.none)
                    ForEach(deviceOptions) { device in
                        Text(device.name).tag(String?.some(device.id))
                    }
                }
                Toggle("Включено", isOn: $draft.enabled)
            }
            .formStyle(.grouped)

            preview

            HStack {
                if !isNew {
                    Button("Удалить", role: .destructive) {
                        state.deleteRemaps([draft.id])
                        dismiss()
                    }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") {
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
        var list = state.devices
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
            Text(isNew ? "Новая комбинация" : "Комбинация").font(.title2.bold())
            Text("Когда нажимаете первую комбинацию, приложение отправляет вместо неё вторую. Например Insert → ⌘V или ⌃C → ⌘C.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Section("Когда нажато") { ChordEditor(chord: $draft.trigger) }
                Section("Отправить") { ChordEditor(chord: $draft.output) }
                Section {
                    TextField("Заметка", text: $draft.note, prompt: Text("например «Вставить»"))
                    Toggle("Включено", isOn: $draft.enabled)
                }
            }
            .formStyle(.grouped)

            if !state.accessibilityGranted {
                Label("Комбинации заработают после разрешения «Универсальный доступ».", systemImage: "lock")
                    .foregroundStyle(.orange)
            }

            HStack {
                if !isNew {
                    Button("Удалить", role: .destructive) {
                        state.deleteCombos([draft.id])
                        dismiss()
                    }
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    state.save(draft)
                    dismiss()
                    if !state.accessibilityGranted { Permissions.openAccessibility() }
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
    @State private var recorder: Any?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                recorder == nil ? startRecording() : stopRecording()
            } label: {
                Text(recorder == nil ? chord.display : "Нажмите сочетание…")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .frame(minWidth: 150)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(recorder == nil ? nil : .accentColor)
            .help("Нажмите и затем нажмите сочетание клавиш")

            Spacer()

            ForEach(ModifierToggle.all) { item in
                Toggle(item.symbol, isOn: modifierBinding(item.flag))
                    .toggleStyle(.button)
                    .help(item.name)
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
            .frame(width: 150)
        }
        .onDisappear(perform: stopRecording)
    }

    private func modifierBinding(_ flag: ModifierSet) -> Binding<Bool> {
        Binding(
            get: { chord.modifiers.contains(flag) },
            set: { on in
                if on { chord.modifiers.insert(flag) } else { chord.modifiers.remove(flag) }
            }
        )
    }

    private func startRecording() {
        state.combos.isPaused = true
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            chord = KeyChord(keyCode: event.keyCode, modifiers: ModifierSet(nsFlags: event.modifierFlags).subtracting(.function))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        state.combos.isPaused = false
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
        .frame(minWidth: 220)
    }
}

/// "Press a key" button: the next physical key press (from any keyboard) is passed to `onCapture`.
struct CaptureButton: View {
    @EnvironmentObject private var state: AppState
    let onCapture: (HIDKeyEvent) -> Void
    @State private var waiting = false

    var body: some View {
        Button(waiting ? "Нажмите клавишу…" : "Нажать") {
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
        .help(state.inputMonitoringGranted ? "Нажмите и затем нажмите клавишу на клавиатуре" : "Нужен доступ к «Мониторингу ввода»")
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
