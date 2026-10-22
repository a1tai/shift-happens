import SwiftUI

struct RemapsScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var selection = Set<UUID>()
    @State private var editing: KeyRemap?
    @State private var showCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                title: "Переназначения",
                subtitle: "Клавиша работает как другая клавиша во всех программах. Применяется системой (hidutil) и восстанавливается после перезагрузки."
            ) {
                Button { showCommand.toggle() } label: { Label("Команда", systemImage: "terminal") }
                    .help("Показать эквивалентную команду для Терминала")
                    .popover(isPresented: $showCommand) {
                        Text(RemapEngine.shellCommand(for: state.config.remaps))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: 600)
                    }
                Button(role: .destructive) { state.deleteRemaps(selection); selection = [] } label: {
                    Label("Удалить", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                Button {
                    let start = HIDUsage(page: HIDPage.keyboard, usage: 0x39)
                    editing = KeyRemap(from: start, to: start, device: state.devices.first)
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if state.config.remaps.isEmpty {
                EmptyState(icon: "arrow.left.arrow.right",
                           text: "Переназначений пока нет. Нажмите «Добавить» или кликните клавишу на экране «Клавиатура».")
            } else {
                Table(state.config.remaps, selection: $selection) {
                    TableColumn("") { remap in
                        Toggle("", isOn: enabledBinding(remap.id)).labelsHidden()
                    }
                    .width(30)
                    TableColumn("Клавиша") { remap in
                        KeyBadge(text: KeyCatalog.name(for: remap.from))
                    }
                    TableColumn("Работает как") { remap in
                        HStack {
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            KeyBadge(text: KeyCatalog.name(for: remap.to), highlighted: remap.enabled)
                        }
                    }
                    TableColumn("Клавиатура") { remap in
                        Text(remap.device?.name ?? "Все клавиатуры")
                            .foregroundStyle(remap.device == nil ? .secondary : .primary)
                    }
                    TableColumn("Коды") { remap in
                        Text("\(remap.from.hexDescription) → \(remap.to.hexDescription)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Изменить…") { editing = state.config.remaps.first { ids.contains($0.id) } }
                        .disabled(ids.count != 1)
                    Button("Удалить", role: .destructive) { state.deleteRemaps(ids) }
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
                title: "Комбинации",
                subtitle: "Одно сочетание клавиш превращается в другое, например Insert → ⌘V. Работает, пока приложение запущено (оно живёт в строке меню)."
            ) {
                Button(role: .destructive) { state.deleteCombos(selection); selection = [] } label: {
                    Label("Удалить", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                Button {
                    let chord = KeyChord(keyCode: 0x72, modifiers: [])
                    editing = ComboBinding(trigger: chord, output: KeyChord(keyCode: 0x09, modifiers: .command))
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if state.config.combos.isEmpty {
                EmptyState(icon: "command",
                           text: "Комбинаций пока нет. Готовые наборы для Windows-клавиатуры есть в «Настройках».")
            } else {
                Table(state.config.combos, selection: $selection) {
                    TableColumn("") { combo in
                        Toggle("", isOn: enabledBinding(combo.id)).labelsHidden()
                    }
                    .width(30)
                    TableColumn("Когда нажато") { combo in
                        KeyBadge(text: combo.trigger.display)
                    }
                    TableColumn("Отправить") { combo in
                        HStack {
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            KeyBadge(text: combo.output.display, highlighted: combo.enabled)
                        }
                    }
                    TableColumn("Заметка") { combo in
                        Text(combo.note).foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Изменить…") { editing = state.config.combos.first { ids.contains($0.id) } }
                        .disabled(ids.count != 1)
                    Button("Удалить", role: .destructive) { state.deleteCombos(ids) }
                } primaryAction: { ids in
                    editing = state.config.combos.first { ids.contains($0.id) }
                }
            }
        }
        .padding(24)
        .sheet(item: $editing) { ComboEditor(combo: $0) }
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
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
            HStack { actions() }
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
