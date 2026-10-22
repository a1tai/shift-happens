import SwiftUI

/// Edits a combo's macro: a list of steps that can be recorded from the keyboard, added by hand,
/// reordered by dragging, duplicated and deleted.
struct MacroEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var combo: ComboBinding
    @State private var recorderID = UUID()
    @State private var recordsDelays = true

    private var isRecording: Bool { state.activeRecorder == recorderID }
    static let delayPresets = [50, 100, 250, 500, 1000]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    isRecording ? state.stopRecording(recorderID) : startRecording()
                } label: {
                    Label(isRecording ? "Stop" : "Record Macro", systemImage: isRecording ? "stop.fill" : "record.circle")
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .red : nil)
                .disabled(!state.inputMonitoringGranted && !isRecording)
                .help(state.inputMonitoringGranted
                      ? "Press keys to add them as steps, then click Stop"
                      : "Recording needs Input Monitoring access. You can still add steps by hand.")
                Toggle("Record delays", isOn: $recordsDelays)
                    .disabled(isRecording)
                    .help("Add the pauses between your key presses as delay steps")
                Spacer()
                Menu {
                    Button("Key Press") { add(.press(KeyChord(keyCode: 0x00, modifiers: []))) }
                    Button("Key Down") { add(.keyDown(KeyChord(keyCode: 0x38, modifiers: []))) }
                    Button("Key Up") { add(.keyUp(KeyChord(keyCode: 0x38, modifiers: []))) }
                    Divider()
                    Button("Delay") { add(.delay(100)) }
                    Button("Type Text") { add(.text("")) }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .fixedSize()
            }

            List {
                ForEach($combo.macro) { $item in
                    MacroStepRow(item: $item)
                        .contextMenu {
                            Button("Duplicate") { duplicate(item.id) }
                            Button("Delete", role: .destructive) { combo.macro.removeAll { $0.id == item.id } }
                        }
                }
                .onMove { combo.macro.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { combo.macro.remove(atOffsets: $0) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 120, idealHeight: 180)
            .overlay {
                if combo.macro.isEmpty {
                    Text(isRecording ? "Press keys…" : "No steps yet. Record a macro or add steps.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Pause between steps")
                TextField("", value: $combo.stepDelay, format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("ms")
                Spacer()
                Picker("", selection: $combo.repeatsWhileHeld) {
                    Text("Run once").tag(false)
                    Text("Repeat while held").tag(true)
                }
                .labelsHidden()
                .fixedSize()
                Text(counted(combo.macro.count, "step") + " · \(combo.macro.duration(stepDelay: combo.stepDelay)) ms")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
        }
        .onDisappear { state.stopRecording(recorderID) }
    }

    /// Appends recorded steps live to the macro's existing steps.
    private func startRecording() {
        let base = combo.macro
        var recorder = MacroRecorder(recordsDelays: recordsDelays)
        var ids: [UUID] = []
        state.startRecording(recorderID)
        state.macroCaptureHandler = { usage, isDown, time in
            recorder.handle(usage, isDown: isDown, at: time)
            while ids.count < recorder.steps.count { ids.append(UUID()) }
            combo.macro = base + zip(ids, recorder.steps).map { MacroItem(id: $0, step: $1) }
        }
    }

    private func add(_ step: MacroStep) {
        combo.macro.append(MacroItem(step: step))
    }

    private func duplicate(_ id: UUID) {
        guard let index = combo.macro.firstIndex(where: { $0.id == id }) else { return }
        combo.macro.insert(MacroItem(step: combo.macro[index].step), at: index + 1)
    }
}

/// One editable macro step.
private struct MacroStepRow: View {
    @Binding var item: MacroItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(kind)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            switch item.step {
            case .press, .keyDown, .keyUp:
                ChordEditor(chord: chordBinding, allowsModifierKeys: true)
            case .delay:
                TextField("", value: delayBinding, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Text("ms").foregroundStyle(.secondary)
                Menu("Presets") {
                    ForEach(MacroEditor.delayPresets, id: \.self) { ms in
                        Button("\(ms) ms") { item.step = .delay(ms) }
                    }
                }
                .fixedSize()
                Spacer()
            case .text:
                TextField("Text to type", text: textBinding)
            }
        }
        .padding(.vertical, 2)
    }

    private var kind: String {
        switch item.step {
        case .press: return "Press"
        case .keyDown: return "Key down"
        case .keyUp: return "Key up"
        case .delay: return "Delay"
        case .text: return "Type"
        }
    }

    private var icon: String {
        switch item.step {
        case .press: return "keyboard"
        case .keyDown: return "arrow.down.to.line"
        case .keyUp: return "arrow.up.to.line"
        case .delay: return "timer"
        case .text: return "textformat"
        }
    }

    private var chordBinding: Binding<KeyChord> {
        Binding(
            get: {
                switch item.step {
                case .press(let c), .keyDown(let c), .keyUp(let c): return c
                default: return KeyChord(keyCode: 0, modifiers: [])
                }
            },
            set: { chord in
                switch item.step {
                case .press: item.step = .press(chord)
                case .keyDown: item.step = .keyDown(chord)
                case .keyUp: item.step = .keyUp(chord)
                default: break
                }
            }
        )
    }

    private var delayBinding: Binding<Int> {
        Binding(
            get: { if case .delay(let ms) = item.step { return ms } else { return 0 } },
            set: { item.step = .delay(max(0, $0)) }
        )
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { if case .text(let text) = item.step { return text } else { return "" } },
            set: { item.step = .text($0) }
        )
    }
}
