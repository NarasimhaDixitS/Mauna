import AppKit
import SwiftUI

/// First launch: three short steps, each with one plain reason (spec › Onboarding).
/// 1. Pick your music player. 2. Apps that usually need quiet (suggested from this Mac). 3. Permissions.
struct OnboardingView: View {
    let model: AppModel
    var onFinish: () -> Void = {}

    @State private var step: Int
    @State private var forward = true
    @State private var suggestions: SuggestionsState

    init(model: AppModel, startStep: Int = 0, suggestions: SuggestionsState = SuggestionsState(), onFinish: @escaping () -> Void = {}) {
        self.model = model
        self.onFinish = onFinish
        _step = State(initialValue: startStep)
        _suggestions = State(initialValue: suggestions)
    }

    /// Landscape: the step and its reason on the left, the choices on the right, buttons along the
    /// bottom. Everything fits at once, so nothing needs scrolling to find.
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    StatusTile(state: .playing, isActing: true, size: 44)
                        .padding(.bottom, 26)
                    header
                    Spacer(minLength: 0)
                }
                .frame(width: 250, alignment: .topLeading)
                .padding(.leading, 36)
                .padding(.trailing, 28)
                .padding(.top, 44)

                ZStack(alignment: .topLeading) {
                    switch step {
                    case 0: PlayersStep(session: model.session).transition(slide)
                    case 1: AppsStep(state: suggestions, coordinator: model.rules).transition(slide)
                    default: PermissionsStep(model: model).transition(slide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 44)
                .padding(.trailing, 36)
                .clipped()
            }

            footer
                .padding(.horizontal, 36)
                .padding(.vertical, 20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .task { await suggestions.load(existing: model.rules) }
    }

    static let size = CGSize(width: 820, height: 520)

    /// Forward and back slide along the same path (DESIGN.md › Motion: onboarding step, 0.3 s).
    private var slide: AnyTransition {
        .asymmetric(
            insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
            removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(LinearGradient.accentFill) : AnyShapeStyle(.well))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            .animation(.maunaSpring, value: step)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title.bold())
                Text(subtitle).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(step)
            .transition(.blurCrossfade)
        }
        .animation(.maunaEaseOut(MotionDuration.onboardingStep), value: step)
    }

    private var title: String {
        switch step {
        case 0: "Pick your music player"
        case 1: "Apps that usually need quiet"
        default: "One last thing"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: "Mauna pauses, fades and brings back this player. It never reads what you listen to. You can switch players any time, from the menu bar or Settings."
        case 1: "Found on your Mac. Tick the ones that should quiet your music. You can change any of this later."
        default: "macOS asks once before Mauna can control your player."
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button("Back") { go(step - 1) }
                    .buttonStyle(.maunaSecondary)
            }
            Spacer()
            if step == 1 {
                Button("Skip for now") { go(2) }
                    .buttonStyle(.maunaGhost)
            }
            Button(step == 2 ? "Done" : continueTitle) {
                if step == 1 { suggestions.addTicked(to: model.rules) }
                if step == 2 {
                    onFinish()
                    // On Free with more rules than Free runs: offer the trial, once, right away.
                    if Store.sellsInApp, !model.unlocksPro, !model.store.trialTaken {
                        model.showUpgrade(for: nil, afterOnboarding: true)
                    }
                } else { go(step + 1) }
            }
            .buttonStyle(.maunaPrimary)
            .keyboardShortcut(.defaultAction)
            .frame(minWidth: 120)
        }
    }

    private var continueTitle: String {
        guard step == 1 else { return "Continue" }
        let count = suggestions.ticked.count
        return count == 0 ? "Continue" : (count == 1 ? "Add 1 app" : "Add \(count) apps")
    }

    private func go(_ next: Int) {
        forward = next > step
        withAnimation(.maunaEaseInOut(MotionDuration.onboardingStep)) { step = next }
    }
}

// MARK: Step 1: players

private struct PlayersStep: View {
    let session: PlayerSession

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(PlayerID.installed.enumerated()), id: \.element) { index, player in
                PlayerOption(player: player, isSelected: session.player == player) { session.select(player) }
                    .staggered(index)
            }
        }
    }
}

private struct PlayerOption: View {
    let player: PlayerID
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                AppIconView(bundleID: player.bundleID, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName).font(.body.weight(.semibold))
                    Text(player.isBrowser ? "Needs one browser setting. Mauna shows you how." : "Works right away.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.tertiary))
            }
            .padding(14)
            .contentShape(Rectangle())
            .elevated(.e2, cornerRadius: 12, fill: .card)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentFill.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5)
            )
            .animation(.maunaEaseOut(0.16), value: isSelected)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: Step 2: suggested apps

@Observable
final class SuggestionsState {
    private(set) var groups: [(group: SuggestionGroup, items: [Suggestion])] = []
    private(set) var isLoading = true
    var ticked: Set<String> = []
    /// Per-app trigger and action, changed from the badge menu.
    var edits: [String: (Trigger, Hold)] = [:]
    @ObservationIgnored private var loaded = false

    func load(existing coordinator: RuleCoordinator) async {
        guard !loaded else { return }
        loaded = true
        let found = Suggestions.suggest(from: await InstalledApps.scan())
        // Apps that already have a rule aren't suggested again.
        groups = found.compactMap { entry in
            let items = entry.items.filter { !coordinator.hasRule(for: $0.app.bundleID) }
            return items.isEmpty ? nil : (entry.group, items)
        }
        ticked = Suggestions.initiallyTicked(groups)
        isLoading = false
    }

    func suggestion(_ item: Suggestion) -> Suggestion {
        var copy = item
        if let (trigger, action) = edits[item.id] { copy.trigger = trigger; copy.action = action }
        return copy
    }

    func addTicked(to coordinator: RuleCoordinator) {
        for item in groups.flatMap(\.items) where ticked.contains(item.id) {
            for rule in suggestion(item).rules { coordinator.add(rule) }
        }
        ticked = []
        groups = groups.compactMap { entry in
            let items = entry.items.filter { !coordinator.hasRule(for: $0.app.bundleID) }
            return items.isEmpty ? nil : (entry.group, items)
        }
    }
}

private struct AppsStep: View {
    let state: SuggestionsState
    let coordinator: RuleCoordinator

    /// Debug renders can't draw scroll views, so snapshots lay the list out flat.
    private var isSnapshot: Bool { ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT"] != nil }

    var body: some View {
        if isSnapshot { list } else { ScrollView { list }.scrollIndicators(.automatic) }
    }

    private var list: some View {
            VStack(alignment: .leading, spacing: 18) {
                if state.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking at your apps…").foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else if state.groups.isEmpty {
                    Text("No common quiet apps found. Add your own below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(state.groups.enumerated()), id: \.element.group) { index, entry in
                    GroupSection(group: entry.group, items: entry.items, state: state)
                        .staggered(index)
                }
                if !coordinator.rules.isEmpty {
                    AddedApps(rules: coordinator.rules)
                }
                AddAppMenu(coordinator: coordinator)
            }
            .padding(.bottom, 12)
            .padding(.horizontal, 2)
    }
}

private struct GroupSection: View {
    let group: SuggestionGroup
    let items: [Suggestion]
    let state: SuggestionsState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.accentText)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.accentTint))
                Text(group.title).font(.headline)
                Text(group.reason).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            SettingsCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SettingsRow(showsDivider: index < items.count - 1) {
                        SuggestionRow(item: state.suggestion(item), state: state)
                    }
                }
            }
        }
    }
}

private struct SuggestionRow: View {
    let item: Suggestion
    let state: SuggestionsState
    private var isTicked: Bool { state.ticked.contains(item.id) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if isTicked { state.ticked.remove(item.id) } else { state.ticked.insert(item.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isTicked ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                    AppIconView(bundleID: item.app.bundleID, size: 28, path: item.app.path)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.app.name).font(.body.weight(.medium)).lineLimit(1)
                        if !item.otherVersions.isEmpty {
                            Text("\(item.otherVersions.count + 1) versions").font(.subheadline).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainTextButtonStyle())
            .accessibilityLabel(item.app.name)
            .accessibilityAddTraits(isTicked ? .isSelected : [])

            Menu {
                Picker("Trigger", selection: triggerBinding) {
                    ForEach(Rule.availableTriggers, id: \.self) { Label($0.name, systemImage: $0.symbol).tag($0) }
                }
                Picker("Action", selection: actionBinding) {
                    Text("Pause").tag(Hold.paused)
                    Text("Lower").tag(Hold.ducked)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: item.trigger.symbol).font(.system(size: 9, weight: .semibold))
                    Text("\(item.trigger.name) · \(item.action == .paused ? "Pause" : "Lower")")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(isTicked ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(isTicked ? AnyShapeStyle(.accentTint) : AnyShapeStyle(.well)))
            }
            .menuStyle(.button)
            .buttonStyle(PlainTextButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change when \(item.app.name) quiets your music")
        }
        .animation(.maunaEaseOut(0.16), value: isTicked)
    }

    private var triggerBinding: Binding<Trigger> {
        Binding(get: { item.trigger }, set: { save(trigger: $0, action: item.action) })
    }

    private var actionBinding: Binding<Hold> {
        Binding(get: { item.action }, set: { save(trigger: item.trigger, action: $0) })
    }

    private func save(trigger: Trigger, action: Hold) {
        state.edits[item.id] = (trigger, action)
        state.ticked.insert(item.id)   // changing it means you want it
    }
}

private struct AddedApps: View {
    let rules: [Rule]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already added").font(.headline)
            HStack(spacing: -6) {
                ForEach(rules.prefix(8)) { AppIconView(bundleID: $0.bundleID, size: 28) }
            }
            Text(rules.map(\.appName).joined(separator: ", "))
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

// MARK: Step 3: permissions

private struct PermissionsStep: View {
    let model: AppModel
    private var session: PlayerSession { model.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(showsDivider: false) {
                    HStack(spacing: 14) {
                        AppIconView(bundleID: session.player.bundleID, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Let Mauna control \(session.player.fullName)").font(.body.weight(.semibold))
                            Text("So it can pause, resume and fade your music.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        permissionAction
                    }
                }
            }
            .staggered(0)

            if session.player.isBrowser {
                SettingsCard {
                    SettingsRow(showsDivider: false) {
                        BrowserSetupGuide(player: session.player, session: session)
                    }
                }
                .staggered(1)
            }

            SettingsCard {
                SettingsRow(showsDivider: false) {
                    HStack(spacing: 14) {
                        WaveGlyphView(state: .ducked, size: 22)
                            .foregroundStyle(Color.onAccent)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient.accentFill))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Quiet music any time").font(.body.weight(.semibold))
                            Text("Press \(model.shortcutText ?? "your shortcut") in any app. Press again to bring it back.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .staggered(2)
        }
    }

    @ViewBuilder private var permissionAction: some View {
        if session.issue == .needsPermission(session.player) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.maunaSmall)
        } else if session.isRunning && session.playback != nil && session.issue == nil {
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.accentText)
        } else if !session.isRunning {
            Button("Open \(session.player.browserName ?? session.player.displayName)") {
                if let url = session.player.appURL {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            .buttonStyle(.maunaSmall)
        } else {
            Button("Allow") { session.refresh() }
                .buttonStyle(.maunaSmall)
        }
    }
}

// MARK: Stagger

private extension View {
    /// Items arrive one after another, 50 ms apart (DESIGN.md › Motion: stagger 40–80 ms).
    func staggered(_ index: Int) -> some View {
        modifier(Stagger(delay: Double(index) * 0.05))
    }
}

private struct Stagger: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.maunaEaseOut(MotionDuration.onboardingStep).delay(delay)) { shown = true }
            }
    }
}
