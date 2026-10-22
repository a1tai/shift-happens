import SwiftUI

struct RemapsScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var selection = Set<UUID>()
    @State private var editing: KeyRemap?
    @State private var showCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                title: "Remaps",
                subtitle: "A key acts as another key in every app. Applied by the system (hidutil) and restored after restart."
            ) {
                Button { showCommand.toggle() } label: { Label("Command", systemImage: "terminal") }
                    .help("Show the equivalent Terminal command")
                    .popover(isPresented: $showCommand) {
                        Text(RemapEngine.shellCommand(for: state.config.remaps))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: 600)
                    }
                Button(role: .destructive) { state.deleteRemaps(selection); selection = [] } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                Button {
                    let start = HIDUsage(page: HIDPage.keyboard, usage: 0x39)
                    editing = KeyRemap(from: start, to: start, device: state.defaultKeyboard)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if state.config.remaps.isEmpty {
                EmptyState(icon: "arrow.left.arrow.right",
                           text: "No remaps yet. Click Add, or click a key on the Keyboard screen.")
            } else {
                Table(state.config.remaps, selection: $selection) {
                    TableColumn("") { remap in
                        Toggle("", isOn: enabledBinding(remap.id)).labelsHidden()
                    }
                    .width(30)
                    TableColumn("Key") { remap in
                        KeyBadge(text: KeyCatalog.name(for: remap.from))
                    }
                    TableColumn("Acts as") { remap in
                        HStack {
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            KeyBadge(text: KeyCatalog.name(for: remap.to), highlighted: remap.enabled)
                        }
                    }
                    TableColumn("Keyboard") { remap in
                        Text(remap.device.map(state.displayName(of:)) ?? "All keyboards")
                            .foregroundStyle(remap.device == nil ? .secondary : .primary)
                    }
                    TableColumn("Codes") { remap in
                        Text("\(remap.from.hexDescription) → \(remap.to.hexDescription)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Edit…") { editing = state.config.remaps.first { ids.contains($0.id) } }
                        .disabled(ids.count != 1)
                    Button("Delete", role: .destructive) { state.deleteRemaps(ids) }
                } primaryAction: { ids in
                    editing = state.config.remaps.first { ids.contains($0.id) }
                }
            }
        }
        .padding(24)
        .sheet(item: $editing) { RemapEditor(remap: $0) }
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { state.config.remaps.first { $0.id == id }?.enabled ?? false },
            set: { on in
                if let index = state.config.remaps.firstIndex(where: { $0.id == id }) {
                    state.config.remaps[index].enabled = on
                }
            }
        )
    }
}

struct CombosScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var selection = Set<UUID>()
    @State private var editing: ComboBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                title: "Combos",
                subtitle: "One key combination turns into another, for example Insert → ⌘V. Works while the app is running (it lives in the menu bar)."
            ) {
                Button(role: .destructive) { state.deleteCombos(selection); selection = [] } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                Button {
                    let chord = KeyChord(keyCode: 0x72, modifiers: [])
                    editing = ComboBinding(trigger: chord, output: KeyChord(keyCode: 0x09, modifiers: .command))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if state.config.combos.isEmpty {
                EmptyState(icon: "command",
                           text: "No combos yet. Presets for Windows keyboards are in Settings.")
            } else {
                Table(state.config.combos, selection: $selection) {
                    TableColumn("") { combo in
                        Toggle("", isOn: enabledBinding(combo.id)).labelsHidden()
                    }
                    .width(30)
                    TableColumn("When pressed") { combo in
                        KeyBadge(text: combo.trigger.display)
                    }
                    TableColumn("Send") { combo in
                        HStack {
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            KeyBadge(text: combo.outputSummary, highlighted: combo.enabled)
                            if combo.isMacro {
                                Text(counted(combo.macro.count, "step")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    TableColumn("Note") { combo in
                        Text(combo.note).foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Edit…") { editing = state.config.combos.first { ids.contains($0.id) } }
                        .disabled(ids.count != 1)
                    Button("Delete", role: .destructive) { state.deleteCombos(ids) }
                } primaryAction: { ids in
                    editing = state.config.combos.first { ids.contains($0.id) }
                }
            }
        }
        .padding(24)
        .sheet(item: $editing) { ComboEditor(combo: $0) }
        .onAppear {
            if DebugSnapshot.opensComboEditor || DebugSnapshot.opensMacroEditor {
                var combo = ComboBinding(trigger: KeyChord(keyCode: 0x69, modifiers: []),
                                         output: KeyChord(keyCode: 0x15, modifiers: [.command, .shift]))
                if DebugSnapshot.opensMacroEditor {
                    combo.macro = [MacroItem(step: .press(KeyChord(keyCode: 0x08, modifiers: .command))),
                                   MacroItem(step: .delay(100)),
                                   MacroItem(step: .keyDown(KeyChord(keyCode: 0x38, modifiers: []))),
                                   MacroItem(step: .press(KeyChord(keyCode: 0x09, modifiers: .command))),
                                   MacroItem(step: .keyUp(KeyChord(keyCode: 0x38, modifiers: []))),
                                   MacroItem(step: .text("Hello"))]
                }
                editing = combo
            }
        }
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { state.config.combos.first { $0.id == id }?.enabled ?? false },
            set: { on in
                if let index = state.config.combos.firstIndex(where: { $0.id == id }) {
                    state.config.combos[index].enabled = on
                }
            }
        )
    }
}

struct ScreenHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
            HStack { actions() }.fixedSize()
        }
    }
}

struct EmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
