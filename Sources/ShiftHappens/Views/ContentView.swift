import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case keyboard, monitor, remaps, combos, layoutFixer, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .monitor: return "Key Monitor"
        case .remaps: return "Remaps"
        case .combos: return "Combos"
        case .layoutFixer: return "Layout Fixer"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .keyboard: return "keyboard"
        case .monitor: return "waveform.path.ecg"
        case .remaps: return "arrow.left.arrow.right"
        case .combos: return "command"
        case .layoutFixer: return "globe"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: SidebarItem? = DebugSnapshot.initialScreen ?? .keyboard

    var body: some View {
        NavigationSplitView {
            // One flat list of screens; Settings sits apart at the bottom, next to the main switch.
            List(selection: $selection) {
                ForEach([SidebarItem.keyboard, .monitor]) { item in
                    Label(item.title, systemImage: item.icon).tag(item)
                }
                Label(SidebarItem.remaps.title, systemImage: SidebarItem.remaps.icon)
                    .badge(state.config.remaps.count)
                    .tag(SidebarItem.remaps)
                Label(SidebarItem.combos.title, systemImage: SidebarItem.combos.icon)
                    .badge(state.config.combos.count)
                    .tag(SidebarItem.combos)
                Label(SidebarItem.layoutFixer.title, systemImage: SidebarItem.layoutFixer.icon)
                    .badge(state.config.layoutFixer.enabled ? Text(state.config.enabled ? "On" : "Paused") : nil)
                    .tag(SidebarItem.layoutFixer)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { StatusFooter(selection: $selection).padding(10) }
        } detail: {
            VStack(spacing: 0) {
                if !DebugSnapshot.hidesBanners { PermissionBanner() }
                Group {
                    switch selection ?? .keyboard {
                    case .keyboard: KeyboardScreen()
                    case .monitor: MonitorScreen()
                    case .remaps: RemapsScreen()
                    case .combos: CombosScreen()
                    case .layoutFixer: LayoutFixerScreen()
                    case .settings: SettingsScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $state.showsOnboarding) {
            OnboardingView().environmentObject(state)
        }
    }
}

/// Settings, the main switch (pauses remaps, combos and the layout fixer together) and a status line.
private struct StatusFooter: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let isSelected = selection == .settings
            Button { selection = .settings } label: {
                Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.icon)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            Toggle(isOn: $state.config.enabled) {
                Text(state.config.enabled ? "Active" : "Paused")
                    .font(.callout.weight(.medium))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .help("Pauses or resumes everything: remaps, combos and the Layout Fixer")
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
                    text: "No Input Monitoring access: the app can't see key codes or notice keyboards being connected.",
                    button: Permissions.wasRequested(.inputMonitoring) ? "Open Settings" : "Allow…",
                    action: { Permissions.request(.inputMonitoring) }
                )
            } else if state.needsRelaunch {
                banner(
                    text: "Input Monitoring is allowed. Relaunch the app to start using it.",
                    button: "Relaunch",
                    action: Permissions.relaunch
                )
            }
            if !state.accessibilityGranted && (usesCombos || state.config.layoutFixer.enabled) {
                banner(
                    text: usesCombos && state.config.layoutFixer.enabled
                        ? "No Accessibility access: combos and the layout fixer don't work."
                        : usesCombos ? "No Accessibility access: combos don't work."
                        : "No Accessibility access: the layout fixer doesn't work.",
                    button: Permissions.wasRequested(.accessibility) ? "Open Settings" : "Allow…",
                    action: { Permissions.request(.accessibility) }
                )
            }
        }
    }

    private var usesCombos: Bool { state.config.combos.contains(where: \.enabled) }

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

/// "1 remap", "3 remaps".
func counted(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}
