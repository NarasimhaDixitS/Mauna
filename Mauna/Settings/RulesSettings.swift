import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Rules: each quiet app with its trigger and Pause or Lower. "Add App…" picks from
/// running apps or the Applications folder, and suggests a trigger (spec › Smart default).
struct RulesSettings: View {
    let model: AppModel
    private var coordinator: RuleCoordinator { model.rules }

    var body: some View {
        SettingsPage(symbol: "app.badge.checkmark", title: "Rules", subtitle: "Apps that quiet your music, and when.") {
            if !coordinator.movedCallApps.isEmpty {
                MovedCallAppsNote(names: coordinator.movedCallApps) {
                    withAnimation(.maunaEaseOut(0.2)) { coordinator.dismissMovedCallNote() }
                }
            }
            if coordinator.rules.isEmpty {
                EmptyRulesCard()
            } else {
                SettingsCard {
                    ForEach(Array(coordinator.rules.enumerated()), id: \.element.id) { index, rule in
                        SettingsRow(showsDivider: index < coordinator.rules.count - 1) {
                            RuleEditorRow(rule: rule, coordinator: coordinator,
                                          isResting: coordinator.isResting(rule), unlocksPro: model.unlocksPro,
                                          upgrade: { model.showUpgrade(for: $0) })
                        }
                    }
                }
            }
            HStack(alignment: .center, spacing: 12) {
                AddAppMenu(coordinator: coordinator, upgrade: model.unlocksPro ? nil : { model.showUpgrade(for: $0) })
                Spacer()
                if Store.sellsInApp, !model.unlocksPro {
                    FreePlanNote { model.showUpgrade(for: nil) }
                }
            }
        }
        .tint(.accentFill)
    }
}

/// Once, after the update: call apps now quiet music only during calls.
private struct MovedCallAppsNote: View {
    let names: [String]
    let dismiss: () -> Void

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.accentText)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.accentTint))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calls, not all day").font(.body.weight(.semibold))
                    Text("\(list) now quiet your music only while you're in a call, not whenever they're open. Change it back anytime with the trigger menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Got It", action: dismiss)
                    .buttonStyle(.maunaSmall)
            }
            .padding(14)
        }
    }

    private var list: String {
        ListFormatter.localizedString(byJoining: names)
    }
}

/// "Free: 2 rules, In front only. PRO" — the limit, said once, plainly, with the way out.
private struct FreePlanNote: View {
    let upgrade: () -> Void

    var body: some View {
        Button(action: upgrade) {
            HStack(spacing: 6) {
                Text("Free: 2 rules, \u{201C}In front\u{201D} only")
                    .foregroundStyle(.secondary)
                ProBadge()
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainTextButtonStyle())
        .help("See what Mauna Pro unlocks")
    }
}

private struct EmptyRulesCard: View {
    var body: some View {
        SettingsCard {
            VStack(spacing: 10) {
                WaveGlyphView(state: .ducked, size: 30)
                    .foregroundStyle(.accentText)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.accentTint))
                Text("No quiet apps yet").font(.headline)
                Text("Add an app, and Mauna will step your music aside when you use it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 40)
        }
    }
}

private struct RuleEditorRow: View {
    let rule: Rule
    let coordinator: RuleCoordinator
    /// On Free past the limit, or needing a Pro feature: kept, but not acting.
    let isResting: Bool
    let unlocksPro: Bool
    let upgrade: (ProFeature) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: rule.bundleID, size: 32)
                .saturation(isResting ? 0.15 : 1)
                .opacity(isResting ? 0.7 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(rule.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(rule.summary)
                    .transition(.blurCrossfade)
                if isResting {
                    Button { upgrade(Entitlement.restReason(for: rule)) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "moon.zzz.fill")
                            Text("Resting on Free")
                            ProBadge()
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.accentText)
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainTextButtonStyle())
                    .help("Mauna Pro brings this rule back")
                }
            }
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: rule.summary)

            Spacer(minLength: 8)

            Picker("Trigger", selection: triggerBinding) {
                ForEach(Rule.availableTriggers, id: \.self) { trigger in
                    Label(unlocksPro || trigger == .inFront ? trigger.name : "\(trigger.name) · Pro", systemImage: trigger.symbol)
                        .tag(trigger)
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Action", selection: actionBinding) {
                Text("Pause").tag(Hold.paused)
                Text("Lower").tag(Hold.ducked)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                coordinator.remove(rule.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(PlainTextButtonStyle())
            .opacity(hovering ? 1 : 0)
            .help("Remove \(rule.appName)")
            .accessibilityLabel("Remove \(rule.appName)")
        }
        .onHover { hovering = $0 }
        .animation(.maunaEaseOut(0.12), value: hovering)
    }

    /// On Free, picking a Pro trigger or Lower opens Mauna Pro instead of changing the rule.
    private var triggerBinding: Binding<Trigger> {
        Binding(get: { rule.trigger }, set: { value in
            if !unlocksPro && value != .inFront { upgrade(.everyTrigger); return }
            var changed = rule
            changed.trigger = value
            coordinator.update(changed)
        })
    }

    private var actionBinding: Binding<Hold> {
        Binding(get: { rule.action }, set: { value in
            if !unlocksPro && value == .ducked { upgrade(.lower); return }
            var changed = rule
            changed.action = value
            coordinator.update(changed)
        })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Rule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { value in
                var changed = rule
                changed[keyPath: keyPath] = value
                coordinator.update(changed)
            }
        )
    }
}

/// Running apps first (the likeliest picks), then the Applications folder.
struct AddAppMenu: View {
    let coordinator: RuleCoordinator
    /// Set on Free outside onboarding: past the limit, the button opens Mauna Pro instead.
    var upgrade: ((ProFeature) -> Void)? = nil

    var body: some View {
        if let upgrade, !Entitlement.canAddOnFree(coordinator.rules) {
            Button { upgrade(.moreRules) } label: {
                HStack(spacing: 6) {
                    Label("Add App…", systemImage: "plus")
                    ProBadge()
                }
            }
            .buttonStyle(.maunaSecondary)
            .fixedSize()
            .help("Free keeps two rules. Mauna Pro adds as many as you like.")
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            let running = runningApps
            if !running.isEmpty {
                Section("Open now") {
                    ForEach(running, id: \.bundleIdentifier) { app in
                        Button {
                            add(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "", url: app.bundleURL)
                        } label: {
                            Label {
                                Text(app.localizedName ?? "")
                            } icon: {
                                Image(nsImage: AppIcon.menuImage(for: app.bundleIdentifier ?? ""))
                            }
                        }
                    }
                }
            }
            Button("Choose from Applications…", action: chooseFromApplications)
        } label: {
            Label("Add App…", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.maunaSecondary)
        .fixedSize()
    }

    private var runningApps: [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        let players = PlayerID.nativeBundleIDs
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return id != own && id != "com.apple.finder" && !players.contains(id) && !coordinator.hasRule(for: id)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseFromApplications() {
        WindowFront.activate()
        let panel = NSOpenPanel()
        panel.title = "Add a quiet app"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(bundleID: id, name: name, url: url)
        }
    }

    private func add(bundleID: String, name: String, url: URL?) {
        guard !bundleID.isEmpty else { return }
        let category = url.flatMap { Bundle(url: $0)?.infoDictionary?["LSApplicationCategoryType"] as? String }
        var trigger = Rule.suggestedTrigger(bundleID: bundleID, category: category)
        // Free in Settings: "In front" only, so the new rule acts instead of resting.
        if upgrade != nil { trigger = .inFront }
        coordinator.add(Rule(bundleID: bundleID, appName: name, trigger: trigger, action: .paused))
    }
}
