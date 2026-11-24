import SwiftUI

enum SettingsTab: String, CaseIterable {
    case players, rules, sound, general, debug
    static let storageKey = "settingsTab"
}

/// Settings window: standard macOS toolbar tabs (design-system.html › Screens).
struct SettingsView: View {
    let model: AppModel
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .rules

    var body: some View {
        TabView(selection: $tab) {
            PlayersSettings(session: model.session)
                .tabItem { Label("Players", systemImage: "music.note") }
                .tag(SettingsTab.players)
            RulesSettings(coordinator: model.rules)
                .tabItem { Label("Rules", systemImage: "list.bullet") }
                .tag(SettingsTab.rules)
            SoundSettings(session: model.session)
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.sound)
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            #if DEBUG
            DebugSettings(model: model)
                .tabItem { Label("Debug", systemImage: "ladybug") }
                .tag(SettingsTab.debug)
            #endif
        }
        .frame(width: Size.settingsWindowWidth)
    }
}

#if DEBUG
/// Phase 1 test controls, kept for testing fades. Only debug builds have this tab.
private struct DebugSettings: View {
    let model: AppModel
    private var session: PlayerSession { model.session }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.s) {
                    Button("Pause") { session.quiet(.pause) }
                        .disabled(session.hold == .paused)
                    Button("Lower") { session.quiet(.duck) }
                        .disabled(session.hold != .none)
                    Button("Restore") { session.release() }
                        .disabled(session.hold == .none)
                }
                .disabled(!session.isRunning)
                Button("Show welcome window") { OnboardingWindow.show(model: model) }
                LabeledContent("Hold", value: "\(session.hold)")
                LabeledContent("Rule hold", value: "\(session.ruleHold)")
                LabeledContent("Your hold", value: "\(session.manualHold)")
                if case .failed(let message) = session.issue {
                    Text(message).foregroundStyle(.failed)
                }
            } footer: {
                Text("Restore works like pressing play: rules in charge step aside until their trigger ends.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
