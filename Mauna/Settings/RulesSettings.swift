import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Rules: each quiet app with its trigger and Pause or Lower. "Add App…" picks from
/// running apps or the Applications folder, and suggests a trigger (spec › Smart default).
struct RulesSettings: View {
    let coordinator: RuleCoordinator

    var body: some View {
        SettingsPage(symbol: "app.badge.checkmark", title: "Rules", subtitle: "Apps that quiet your music, and when.") {
            if coordinator.rules.isEmpty {
                EmptyRulesCard()
            } else {
                SettingsCard {
                    ForEach(Array(coordinator.rules.enumerated()), id: \.element.id) { index, rule in
                        SettingsRow(showsDivider: index < coordinator.rules.count - 1) {
                            RuleEditorRow(rule: rule, coordinator: coordinator)
                        }
                    }
                }
            }
            AddAppMenu(coordinator: coordinator)
        }
        .tint(.accentFill)
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: rule.bundleID, size: 32)

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
            }
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: rule.summary)

            Spacer(minLength: 8)

            Picker("Trigger", selection: binding(\.trigger)) {
                ForEach(Rule.availableTriggers, id: \.self) { trigger in
                    Label(trigger.name, systemImage: trigger.symbol).tag(trigger)
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Action", selection: binding(\.action)) {
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
private struct AddAppMenu: View {
    let coordinator: RuleCoordinator

    var body: some View {
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
        let players = Set(PlayerID.allCases.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return id != own && id != "com.apple.finder" && !players.contains(id) && !coordinator.hasRule(for: id)
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseFromApplications() {
        NSApplication.shared.activate()
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
        let trigger = Rule.suggestedTrigger(bundleID: bundleID, category: category)
        coordinator.add(Rule(bundleID: bundleID, appName: name, trigger: trigger, action: .paused))
    }
}
