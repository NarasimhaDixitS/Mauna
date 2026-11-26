import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Launch at login and the quiet shortcut.
struct GeneralSettings: View {
    let model: AppModel
    @AppStorage(QuietShortcut.Mode.storageKey) private var mode: QuietShortcut.Mode = .pause

    var body: some View {
        SettingsPage(symbol: "gearshape.fill", title: "General", subtitle: "Startup and the quiet shortcut.") {
            SettingsCard {
                SettingsRow(showsDivider: false) {
                    LaunchAtLoginToggle()
                }
            }

            SettingsCard {
                SettingsRow {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quiet shortcut").font(.body.weight(.medium))
                            Text("Press once to quiet music from any app, again to bring it back.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .quietMusic)
                    }
                }
                SettingsRow(showsDivider: false) {
                    HStack {
                        Text("When pressed").font(.body.weight(.medium))
                        Spacer()
                        Picker("When pressed", selection: $mode) {
                            ForEach(QuietShortcut.Mode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
        .tint(.accentFill)
    }
}

/// SMAppService login item. Reads the real status each time, since the user can change it in System Settings.
private struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { set($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Mauna at login").font(.body.weight(.medium))
                    Text("Mauna starts quietly in the menu bar.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            if status == .requiresApproval {
                HStack {
                    Text("Allow Mauna in Login Items to finish.")
                        .font(.callout)
                        .foregroundStyle(.needsSetup)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
            } else if failed {
                Text("Couldn't change this. Try again from Login Items in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.failed)
            }
        }
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failed = false
        } catch {
            failed = true
        }
        status = SMAppService.mainApp.status
    }
}
