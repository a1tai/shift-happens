import SwiftUI

/// One permission with its live state and the buttons that get it granted.
struct PermissionStatusRow: View {
    @EnvironmentObject private var state: AppState
    let permission: Permission
    var optional = false

    private var granted: Bool {
        permission == .inputMonitoring ? state.inputMonitoringGranted : state.accessibilityGranted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(permission.title).font(.headline)
                    if optional {
                        Text("Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                Text(permission.reason).font(.callout).foregroundStyle(.secondary)
                if !granted && Permissions.wasRequested(permission) {
                    // A rebuilt app has a new signature, but System Settings keeps showing the old entry as on.
                    Text("Already switched on in System Settings? That entry may belong to an older build.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Reset and Ask Again") { Permissions.resetAndRequest(permission) }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
                if permission == .inputMonitoring && granted && state.needsRelaunch {
                    Text("Allowed. Relaunch the app to start using it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if permission == .inputMonitoring && granted && state.needsRelaunch {
                Button("Relaunch", action: Permissions.relaunch)
            } else if !granted {
                Button(Permissions.wasRequested(permission) ? "Open Settings" : "Allow…") {
                    Permissions.request(permission)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The first-launch sheet that asks for both permissions.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState

    private var allGranted: Bool { state.inputMonitoringGranted && state.accessibilityGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Shift Happens").font(.title2.bold())
                    Text("macOS asks before an app may read or change what you type. Allow these two and you're set.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                PermissionStatusRow(permission: .inputMonitoring)
                    .padding(12)
                Divider()
                PermissionStatusRow(permission: .accessibility, optional: true)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

            Text("Each button shows macOS's own dialog. If macOS has asked before, it opens System Settings instead: "
                 + "switch Shift Happens on there and come back. This window updates by itself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                if !allGranted {
                    Button("Later") { state.finishOnboarding() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(allGranted ? "Done" : "Continue") { state.finishOnboarding() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
