import SwiftUI

/// Edits a combo's macro: a list of steps that can be recorded from the keyboard or added by hand,
/// with the usual list controls below it (add, remove, duplicate, move, insert delay, simplify, clear).
struct MacroEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var combo: ComboBinding
    @State private var selection = Set<UUID>()
    @State private var recorderID = UUID()
    @State private var recordsDelays = true
    @State private var confirmClear = false
    @State private var showsSimplify = false
    @State private var simplifyBelow = 30

    private var isRecording: Bool { state.activeRecorder == recorderID }
    static let delayPresets = [50, 100, 250, 500, 1000]

    /// Index after the last selected step, where new and recorded steps go; the end if nothing is selected.
    private var insertionIndex: Int {
        let indices = combo.macro.indices.filter { selection.contains(combo.macro[$0].id) }
        return (indices.max() ?? combo.macro.count - 1) + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach($combo.macro) { $item in
                    MacroStepRow(item: $item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Duplicate") { duplicate([item.id]) }
                            Button("Insert Delay After") { insertDelay(after: item.id) }
                            Divider()
                            Button("Delete", role: .destructive) { remove([item.id]) }
                        }
                }
                .onMove { combo.macro.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand { remove(selection) }
            .overlay {
                if combo.macro.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "keyboard.badge.ellipsis").font(.largeTitle).foregroundStyle(.tertiary)
                        Text(isRecording ? "Press keys… Click Stop when done." : "No steps yet")
                            .font(.headline).foregroundStyle(.secondary)
                        if !isRecording {
                            Text("Record your key presses, or add steps with +.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            toolbar
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        .onDisappear { state.stopRecording(recorderID) }
        .confirmationDialog("Remove all \(combo.macro.count) steps?", isPresented: $confirmClear) {
            Button("Clear All", role: .destructive) {
                combo.macro.removeAll()
                selection.removeAll()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Key Press") { add(.press(KeyChord(keyCode: 0x00, modifiers: []))) }
                Button("Key Down") { add(.keyDown(KeyChord(keyCode: 0x38, modifiers: []))) }
                Button("Key Up") { add(.keyUp(KeyChord(keyCode: 0x38, modifiers: []))) }
                Divider()
                Button("Delay") { add(.delay(100)) }
                Button("Type Text") { add(.text("")) }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("Add a step after the selection")

            toolButton("minus", help: "Remove the selected steps (Delete)", disabled: selection.isEmpty) { remove(selection) }
            toolButton("plus.square.on.square", help: "Duplicate the selected steps (⌘D)", disabled: selection.isEmpty) {
                duplicate(selection)
            }
            .keyboardShortcut("d", modifiers: .command)
            toolButton("arrow.up", help: "Move up", disabled: selection.isEmpty) { move(by: -1) }
            toolButton("arrow.down", help: "Move down", disabled: selection.isEmpty) { move(by: 1) }
            toolButton("timer", help: "Insert a 100 ms delay after the selection") {
                combo.macro.insert(MacroItem(step: .delay(100)), at: insertionIndex)
            }
            toolButton("wand.and.stars", help: "Simplify: merge key down + up into presses, drop short delays",
                       disabled: combo.macro.isEmpty) { showsSimplify = true }
                .popover(isPresented: $showsSimplify, arrowEdge: .bottom) { simplifyPopover }
            toolButton("trash", help: "Remove all steps", disabled: combo.macro.isEmpty) { confirmClear = true }

            Divider().frame(height: 16).padding(.horizontal, 6)

            Button {
                isRecording ? state.stopRecording(recorderID) : startRecording()
            } label: {
                Label(isRecording ? "Stop" : "Record", systemImage: isRecording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isRecording ? Color.red : Color.primary)
            .disabled(!state.inputMonitoringGranted && !isRecording)
            .help(state.inputMonitoringGranted
                  ? "Record key presses after the selection. Click Stop when done."
                  : "Recording needs Input Monitoring access. You can still add steps by hand.")
            Toggle("Record delays", isOn: $recordsDelays)
                .toggleStyle(.checkbox)
                .disabled(isRecording)
                .help("Add the pauses between your key presses as delay steps")

            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Pause between steps")
            TextField("", value: $combo.stepDelay, format: .number)
                .frame(width: 50)
                .multilineTextAlignment(.trailing)
            Text("ms").foregroundStyle(.secondary)
            Picker("", selection: $combo.repeatsWhileHeld) {
                Text("Run once").tag(false)
                Text("Repeat while held").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            .help("Holding the trigger key plays the macro once, or again and again")
            Spacer()
            Text(counted(combo.macro.count, "step") + " · \(combo.macro.duration(stepDelay: combo.stepDelay)) ms")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toolButton(_ icon: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
    }

    private var simplifyPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simplify").font(.headline)
            Text("Turns a key down followed by its key up into one press,\nand removes delays shorter than:")
                .foregroundStyle(.secondary)
            HStack {
                TextField("", value: $simplifyBelow, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
                Text("ms")
                Spacer()
                Button("Simplify") {
                    combo.macro = combo.macro.simplified(minimumDelay: simplifyBelow)
                    selection.removeAll()
                    showsSimplify = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: - Editing

    private func add(_ step: MacroStep) {
        let item = MacroItem(step: step)
        combo.macro.insert(item, at: insertionIndex)
        selection = [item.id]
    }

    private func remove(_ ids: Set<UUID>) {
        combo.macro.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    private func duplicate(_ ids: Set<UUID>) {
        let copies = combo.macro.filter { ids.contains($0.id) }.map { MacroItem(step: $0.step) }
        combo.macro.insert(contentsOf: copies, at: insertionIndex)
        selection = Set(copies.map(\.id))
    }

    private func insertDelay(after id: UUID) {
        guard let index = combo.macro.firstIndex(where: { $0.id == id }) else { return }
        combo.macro.insert(MacroItem(step: .delay(100)), at: index + 1)
    }

    /// Moves the selected steps one place up or down, keeping their order.
    private func move(by offset: Int) {
        var items = combo.macro
        let order = offset < 0 ? Array(items.indices) : Array(items.indices.reversed())
        for index in order where selection.contains(items[index].id) {
            let target = index + offset
            guard items.indices.contains(target), !selection.contains(items[target].id) else { continue }
            items.swapAt(index, target)
        }
        combo.macro = items
    }

    /// Records key presses and inserts them live after the selection (or at the end).
    private func startRecording() {
        let before = Array(combo.macro[..<insertionIndex])
        let after = Array(combo.macro[insertionIndex...])
        var recorder = MacroRecorder(recordsDelays: recordsDelays)
        var ids: [UUID] = []
        state.startRecording(recorderID)
        state.macroCaptureHandler = { usage, isDown, time in
            recorder.handle(usage, isDown: isDown, at: time)
            while ids.count < recorder.steps.count { ids.append(UUID()) }
            combo.macro = before + zip(ids, recorder.steps).map { MacroItem(id: $0, step: $1) } + after
        }
    }
}

/// One editable macro step, in columns: icon and type, then the key or value.
private struct MacroStepRow: View {
    @Binding var item: MacroItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(kind)
                .frame(width: 72, alignment: .leading)
            switch item.step {
            case .press, .keyDown, .keyUp:
                ChordEditor(chord: chordBinding, allowsModifierKeys: true, compact: true)
            case .delay:
                TextField("", value: delayBinding, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Text("ms").foregroundStyle(.secondary)
                Menu {
                    ForEach(MacroEditor.delayPresets, id: \.self) { ms in
                        Button("\(ms) ms") { item.step = .delay(ms) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Common delays")
            case .text:
                TextField("Text to type", text: textBinding)
                    .frame(maxWidth: 320)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private var kind: String {
        switch item.step {
        case .press: return "Press"
        case .keyDown: return "Key down"
        case .keyUp: return "Key up"
        case .delay: return "Delay"
        case .text: return "Type text"
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
