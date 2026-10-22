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
    @State private var showsShortcutInsert = false
    @State private var shortcutToInsert = KeyChord(keyCode: 0x08, modifiers: .command)

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
                Button("Key Down") { add([.keyDown(KeyChord(keyCode: 0x00, modifiers: []))]) }
                Button("Key Up") { add([.keyUp(KeyChord(keyCode: 0x00, modifiers: []))]) }
                Button("Delay") { add([.delay(100)]) }
                Button("Type Text") { add([.text("")]) }
                Divider()
                Button("Key Press (Down + Up)") {
                    let key = KeyChord(keyCode: 0x00, modifiers: [])
                    add([.keyDown(key), .keyUp(key)])
                }
                Button("Shortcut…") { showsShortcutInsert = true }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("Add steps after the selection")
            .popover(isPresented: $showsShortcutInsert, arrowEdge: .bottom) { shortcutPopover }

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
            toolButton("wand.and.stars", help: "Remove short delays and merge delays that follow each other",
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
            if let warning = unmatchedWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .help("Playback still releases every key at the end, so nothing stays stuck.")
            }
            Text(counted(combo.macro.count, "step") + " · \(combo.macro.duration(stepDelay: combo.stepDelay)) ms")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// A short note about key steps that don't pair up (not an error; playback releases everything).
    private var unmatchedWarning: String? {
        let (upWithoutDown, neverReleased) = combo.macro.unmatchedKeys
        if let key = neverReleased.first { return "\(key.keyName) is never released" }
        if let key = upWithoutDown.first { return "\(key.keyName) is released without being pressed" }
        return nil
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
            Text("Clean Up Delays").font(.headline)
            Text("Removes delays shorter than this and merges delays\nthat follow each other. Key steps stay as they are.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("", value: $simplifyBelow, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
                Text("ms")
                Spacer()
                Button("Clean Up") {
                    combo.macro = combo.macro.withoutShortDelays(below: simplifyBelow)
                    selection.removeAll()
                    showsSimplify = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private var shortcutPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insert Shortcut").font(.headline)
            Text("Adds its key events: modifiers down, key down, key up, modifiers up.")
                .foregroundStyle(.secondary)
            ChordEditor(chord: $shortcutToInsert, compact: true)
            HStack {
                Spacer()
                Button("Insert") {
                    add(MacroStep.events(for: shortcutToInsert))
                    showsShortcutInsert = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }

    // MARK: - Editing

    private func add(_ steps: [MacroStep]) {
        let items = steps.map { MacroItem(step: $0) }
        combo.macro.insert(contentsOf: items, at: insertionIndex)
        selection = Set(items.map(\.id))
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

/// One editable macro step, in columns: direction or type, then the key or value.
private struct MacroStepRow: View {
    @EnvironmentObject private var state: AppState
    @Binding var item: MacroItem
    @State private var isEditingText = false
    /// The text before editing started, for Esc.
    @State private var textBeforeEditing = ""
    @FocusState private var focusedField: Field?

    private enum Field { case delay, text }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            Text(kind)
                .frame(width: 72, alignment: .leading)
            switch item.step {
            case .keyDown, .keyUp, .press:
                MacroKeyField(key: keyBinding)
            case .delay:
                TextField("", value: delayBinding, format: .number)
                    .focused($focusedField, equals: .delay)
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
                textStep
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        // Return in a step's field finishes editing it; it must not save and close the sheet.
        .onChange(of: focusedField) { field in state.isEditingMacroField = field != nil }
        .onDisappear { if focusedField != nil { state.isEditingMacroField = false } }
    }

    /// Shown as text; double-click to edit, Return to finish, Esc to undo the edit.
    @ViewBuilder
    private var textStep: some View {
        if isEditingText {
            TextField("Text to type", text: textBinding)
                .focused($focusedField, equals: .text)
                .frame(maxWidth: 320)
                .onSubmit { isEditingText = false }
                .onExitCommand {
                    textBinding.wrappedValue = textBeforeEditing
                    isEditingText = false
                }
                .onAppear { focusedField = .text }
                .onChange(of: focusedField) { field in if field != .text { isEditingText = false } }
        } else {
            Text(textBinding.wrappedValue.isEmpty ? "Double-click to enter text" : "“\(textBinding.wrappedValue)”")
                .foregroundStyle(textBinding.wrappedValue.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: 320, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    textBeforeEditing = textBinding.wrappedValue
                    isEditingText = true
                }
                .help("Double-click to edit")
        }
    }

    private var kind: String {
        switch item.step {
        case .press: return "Press"
        case .keyDown: return "Down"
        case .keyUp: return "Up"
        case .delay: return "Delay"
        case .text: return "Type text"
        }
    }

    private var icon: String {
        switch item.step {
        case .press: return "keyboard"
        case .keyDown: return "arrow.down"
        case .keyUp: return "arrow.up"
        case .delay: return "timer"
        case .text: return "textformat"
        }
    }

    private var iconColor: Color {
        switch item.step {
        case .keyDown: return .accentColor
        case .keyUp: return .orange
        default: return .secondary
        }
    }

    private var keyBinding: Binding<KeyChord> {
        Binding(
            get: {
                switch item.step {
                case .press(let c), .keyDown(let c), .keyUp(let c): return c
                default: return KeyChord(keyCode: 0, modifiers: [])
                }
            },
            set: { key in
                switch item.step {
                case .press: item.step = .press(key)
                case .keyDown: item.step = .keyDown(key)
                case .keyUp: item.step = .keyUp(key)
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

/// One key of a macro step, modifiers included as keys of their own: click to press it, or pick it.
private struct MacroKeyField: View {
    @EnvironmentObject private var state: AppState
    @Binding var key: KeyChord
    @State private var recorderID = UUID()

    private var isRecording: Bool { state.activeRecorder == recorderID }

    var body: some View {
        KeyFieldShell(text: key.keyName, isRecording: isRecording, minWidth: 190, onClick: toggle) {
            KeyMenuItems(keys: KeyCatalog.chordKeysWithModifiers) { def in
                if let code = def.macKeyCode { key = KeyChord(keyCode: code, modifiers: []) }
            }
        }
        .help(isRecording ? "Press a key. Esc cancels." : "Click and press a key, or pick one with the arrow")
        .onDisappear { state.stopRecording(recorderID) }
    }

    private func toggle() {
        if isRecording {
            state.stopRecording(recorderID)
        } else if state.inputMonitoringGranted {
            state.startRecording(recorderID)
            listen()
        }
    }

    /// Takes the next key press as macOS sees it (after the remaps); fn is ignored, so recording goes on.
    private func listen() {
        state.captureHandler = { event in
            guard let code = KeyCatalog.key(for: state.remapped(event.usage, from: event.device))?.macKeyCode,
                  code != KeyCatalog.fnKeyCode else { listen(); return }
            key = KeyChord(keyCode: code, modifiers: [])
            state.stopRecording(recorderID)
        }
    }
}
