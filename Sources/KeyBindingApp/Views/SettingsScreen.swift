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
            Section {
                PermissionStatusRow(permission: .inputMonitoring)
                PermissionStatusRow(permission: .accessibility, optional: true)
            } header: {
                HStack {
                    Text("Permissions")
                    Spacer()
                    Button("Show Welcome Guide…") { state.showsOnboarding = true }
                        .controlSize(.small)
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Text("The app starts in the background, reapplies all bindings and stays in the menu bar. Move the app to the Applications folder before turning this on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("After restart")
            }

            Section("Presets for Windows keyboards") {
                Picker("Keyboard for remaps", selection: $presetDeviceID) {
                    Text("All keyboards").tag(String?.none)
                    ForEach(state.devices) { Text($0.name).tag(String?.some($0.id)) }
                }
                ForEach(Preset.allCases) { preset in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                            Text(preset.details).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") {
                            preset.apply(to: state, device: state.devices.first { $0.id == presetDeviceID })
                            message = "Added preset “\(preset.title)”."
                        }
                    }
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            Section("Backup") {
                HStack {
                    Button("Export…", action: exportConfig)
                    Button("Import…", action: importConfig)
                    Spacer()
                    Button("Show settings file") {
                        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
                    }
                }
                Text(ConfigStore.fileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                Button("Delete all bindings…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all remaps and combos?", isPresented: $confirmReset) {
            Button("Delete all", role: .destructive) { state.resetAll() }
        } message: {
            Text("The keyboard immediately goes back to normal.")
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
        panel.nameFieldStringValue = "Shift Happens.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigStore.encode(state.config).write(to: url, options: .atomic)
            message = "Settings saved to \(url.lastPathComponent)."
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
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
            message = "Imported \(counted(imported.remaps.count, "remap")) and \(counted(imported.combos.count, "combo"))."
        } catch {
            message = "Couldn't read the file: \(error.localizedDescription)"
        }
    }
}
