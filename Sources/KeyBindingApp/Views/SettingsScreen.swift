import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var presetDeviceID: String?
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Разрешения") {
                PermissionRow(
                    title: "Мониторинг ввода",
                    details: "Чтобы видеть коды клавиш и узнавать, с какой клавиатуры они пришли.",
                    granted: state.inputMonitoringGranted,
                    action: Permissions.openInputMonitoring
                )
                PermissionRow(
                    title: "Универсальный доступ",
                    details: "Чтобы превращать одни сочетания клавиш в другие.",
                    granted: state.accessibilityGranted,
                    action: Permissions.openAccessibility
                )
            }

            Section {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Text("Приложение стартует в фоне, снова применяет все привязки и остаётся в строке меню. Перед включением переместите приложение в папку «Программы».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("После перезагрузки")
            }

            Section("Готовые наборы для Windows-клавиатуры") {
                Picker("Клавиатура для переназначений", selection: $presetDeviceID) {
                    Text("Все клавиатуры").tag(String?.none)
                    ForEach(state.devices) { Text($0.name).tag(String?.some($0.id)) }
                }
                ForEach(Preset.allCases) { preset in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                            Text(preset.details).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Добавить") {
                            preset.apply(to: state, device: state.devices.first { $0.id == presetDeviceID })
                            message = "Набор «\(preset.title)» добавлен."
                        }
                    }
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            Section("Резервная копия") {
                HStack {
                    Button("Экспорт…", action: exportConfig)
                    Button("Импорт…", action: importConfig)
                    Spacer()
                    Button("Показать файл настроек") {
                        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
                    }
                }
                Text(ConfigStore.fileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                Button("Удалить все привязки…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Удалить все переназначения и комбинации?", isPresented: $confirmReset) {
            Button("Удалить всё", role: .destructive) { state.resetAll() }
        } message: {
            Text("Клавиатура сразу вернётся к обычному поведению.")
        }
        .onAppear {
            // Most likely the user wants presets for the external (Windows) keyboard.
            if presetDeviceID == nil {
                presetDeviceID = state.devices.first { !$0.name.localizedCaseInsensitiveContains("Apple") }?.id
            }
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "KeyBindingApp.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigStore.encode(state.config).write(to: url, options: .atomic)
            message = "Настройки сохранены в \(url.lastPathComponent)."
        } catch {
            message = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
            var config = state.config
            config.remaps = imported.remaps
            config.combos = imported.combos
            config.knownDevices = Array(Set(config.knownDevices + imported.knownDevices))
            state.config = config
            message = "Импортировано: \(imported.remaps.count) переназначений, \(imported.combos.count) комбинаций."
        } catch {
            message = "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let details: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(details).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Открыть настройки", action: action)
            }
        }
    }
}
