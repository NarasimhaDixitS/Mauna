import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case players, rules, sound, general, pro, debug
    static let storageKey = "settingsTab"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .players: "Players"
        case .rules: "Rules"
        case .sound: "Sound"
        case .general: "General"
        case .pro: "Mauna Pro"
        case .debug: "Debug"
        }
    }

    var symbol: String {
        switch self {
        case .players: "music.note"
        case .rules: "app.badge.checkmark"
        case .sound: "speaker.wave.2.fill"
        case .general: "gearshape.fill"
        case .pro: "sparkle"
        case .debug: "ladybug.fill"
        }
    }

    /// Tabs this build shows. Pro only where it's sold; Debug only in debug builds.
    static var visible: [SettingsTab] {
        var tabs: [SettingsTab] = [.players, .rules, .sound, .general]
        if Store.sellsInApp { tabs.append(.pro) }
        #if DEBUG
        // Staged App Store screenshots show Settings as customers see it.
        if ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_STAGE"] == nil { tabs.append(.debug) }
        #endif
        return tabs
    }
}

/// Settings: a fixed landscape window like System Settings. A sidebar of tabs on the left, the page
/// on the right. Same size for every tab, so switching is instant and nothing jumps.
struct SettingsView: View {
    let model: AppModel
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .rules

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $tab, plan: model.store.plan)
                .frame(width: Size.settingsSidebarWidth)
            Rectangle().fill(.hairline).frame(width: 0.5)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(tab)
        }
        .frame(width: Size.settingsWindow.width,
               height: ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT"] == nil ? Size.settingsWindow.height : nil)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .players: PlayersSettings(model: model)
        case .rules: RulesSettings(model: model)
        case .sound: SoundSettings(model: model)
        case .general: GeneralSettings(model: model)
        case .pro: ProSettings(model: model)
        case .debug:
            #if DEBUG
            DebugSettings(model: model)
            #else
            EmptyView()
            #endif
        }
    }
}

/// The tab list: a small gold tile and a name per tab; the selected one sits on a soft gold tint.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.visible) { tab in
                Button { selection = tab } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.onAccent)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(LinearGradient.accentFill))
                        Text(tab.title)
                            .font(.body.weight(selection == tab ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if tab == .pro, plan == .pro { ProBadge() }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient.accentRowTint)
                            .opacity(selection == tab ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainTextButtonStyle())
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.well.opacity(0.5))
    }
}

#if DEBUG
/// Phase 1 test controls, kept for testing fades. Only debug builds have this tab.
private struct DebugSettings: View {
    let model: AppModel
    private var session: PlayerSession { model.session }
    /// Testing Pro without buying: pretend to be on a plan. "As purchased" goes back to StoreKit.
    @State private var previewPlan = "real"

    private func setPlan(_ choice: String) {
        previewPlan = choice
        let store = model.store
        switch choice {
        case "free": store.preview(.free, trialTaken: false)
        case "trial": store.preview(.trial(endsAt: .now.addingTimeInterval(5 * 86_400 - 60)), trialTaken: true)
        case "ended": store.preview(.free, trialTaken: true)
        case "pro": store.preview(.pro)
        default: Task { await store.endPreview() }
        }
    }

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
                Picker("Plan", selection: Binding(get: { previewPlan }, set: { setPlan($0) })) {
                    Text("As purchased").tag("real")
                    Text("Free").tag("free")
                    Text("Trial, 9 days left").tag("trial")
                    Text("Trial ended").tag("ended")
                    Text("Pro").tag("pro")
                }
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
