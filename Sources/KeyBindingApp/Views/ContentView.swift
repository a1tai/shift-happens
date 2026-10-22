import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case keyboard, monitor, remaps, combos, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: return "Клавиатура"
        case .monitor: return "Монитор клавиш"
        case .remaps: return "Переназначения"
        case .combos: return "Комбинации"
        case .settings: return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .keyboard: return "keyboard"
        case .monitor: return "waveform.path.ecg"
        case .remaps: return "arrow.left.arrow.right"
        case .combos: return "command"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: SidebarItem? = .keyboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach([SidebarItem.keyboard, .monitor]) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                Section("Привязки") {
                    Label(SidebarItem.remaps.title, systemImage: SidebarItem.remaps.icon)
                        .badge(state.config.remaps.count)
                        .tag(SidebarItem.remaps)
                    Label(SidebarItem.combos.title, systemImage: SidebarItem.combos.icon)
                        .badge(state.config.combos.count)
                        .tag(SidebarItem.combos)
                }
                Section {
                    Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.icon)
                        .tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { StatusFooter().padding(12) }
        } detail: {
            VStack(spacing: 0) {
                PermissionBanner()
                Group {
                    switch selection ?? .keyboard {
                    case .keyboard: KeyboardScreen()
                    case .monitor: MonitorScreen()
                    case .remaps: RemapsScreen()
                    case .combos: CombosScreen()
                    case .settings: SettingsScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Master switch plus a short status line at the bottom of the sidebar.
private struct StatusFooter: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $state.config.enabled) {
                Text(state.config.enabled ? "Привязки включены" : "Привязки выключены")
                    .font(.callout.weight(.medium))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Explains which permission is missing and opens the right System Settings pane.
struct PermissionBanner: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if !state.inputMonitoringGranted {
                banner(
                    text: "Нет доступа к «Мониторингу ввода»: приложение не видит коды клавиш и не замечает подключение клавиатуры.",
                    button: "Открыть настройки",
                    action: Permissions.openInputMonitoring
                )
            }
            if !state.accessibilityGranted && state.config.combos.contains(where: \.enabled) {
                banner(
                    text: "Нет доступа к «Универсальному доступу»: комбинации клавиш не работают.",
                    button: "Разрешить",
                    action: Permissions.openAccessibility
                )
            }
        }
    }

    private func banner(text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            Button(button, action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}
