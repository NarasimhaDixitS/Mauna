import AppKit
import Foundation
import Observation

/// Owns the rules (saved, plus quick "until it quits" ones) and the on/off switch,
/// and connects the app watcher to the rule engine, and the engine's decision to the player.
@Observable
final class RuleCoordinator {
    private(set) var decision = RuleEngine.Decision()
    /// True while a change is waiting out the debounce. The popover shows it.
    private(set) var isWaiting = false
    /// True while nobody is at the Mac. Rules hold still.
    private(set) var isAway = false

    /// Your rules, in the order you added them. Saved.
    private(set) var rules: [Rule]
    /// Quick rules from the popover ("Pause until Safari quits"). Gone when the app quits. Not saved.
    private(set) var quickRules: [Rule] = []
    /// The master switch. Off: rules leave the music alone. The quiet shortcut still works.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            // You flipped the switch: rules that apply right now act at once, no 1.5 s wait.
            pushRules(activatingNow: isEnabled ? Set(allRules.map(\.id)) : [])
        }
    }
    /// The app in front, as rules see it (never Mauna itself).
    private(set) var frontmost: String?

    @ObservationIgnored private var engine: RuleEngine
    @ObservationIgnored private let watcher = AppWatcher()
    @ObservationIgnored private let session: PlayerSession
    @ObservationIgnored private var timer: Task<Void, Never>?

    private enum Keys {
        static let rules = "rules"
        static let enabled = "isEnabled"
    }

    init(session: PlayerSession) {
        self.session = session
        let defaults = UserDefaults.standard
        self.rules = defaults.data(forKey: Keys.rules).flatMap { try? JSONDecoder().decode([Rule].self, from: $0) } ?? []
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        self.engine = RuleEngine(rules: [])

        watcher.onChange = { [weak self] snapshot in self?.update(snapshot) }
        watcher.onAwayChange = { [weak self] away in
            guard let self else { return }
            isAway = away
            engine.setAway(away, now: Self.now)
            publish()
            scheduleNext()
        }
        session.onUserOverride = { [weak self] in
            guard let self else { return }
            engine.userOverrode()
            publish()
        }
        frontmost = watcher.snapshot.frontmost
        pushRules()
    }

    // MARK: Editing rules

    /// All rules the engine sees, saved first.
    var allRules: [Rule] { rules + quickRules }

    func add(_ rule: Rule) {
        guard !hasRule(for: rule.bundleID) else { return }
        rules.append(rule)
        save()
        pushRules(activatingNow: [rule.id])
    }

    func update(_ rule: Rule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }), rules[index] != rule else { return }
        rules[index] = rule
        save()
        pushRules(activatingNow: [rule.id])
    }

    func remove(_ id: Rule.ID) {
        rules.removeAll { $0.id == id }
        quickRules.removeAll { $0.id == id }
        save()
        pushRules()
    }

    /// "Pause until Safari quits": a Running rule that lasts until the app quits. Acts at once.
    func addQuickRule(bundleID: String, appName: String, action: Hold) {
        guard !hasRule(for: bundleID) else { return }
        let rule = Rule(bundleID: bundleID, appName: appName, trigger: .running, action: action)
        quickRules.append(rule)
        pushRules(activatingNow: [rule.id])
    }

    /// "Make it a rule": keep a quick rule after the app quits.
    func keep(_ quickRule: Rule) {
        guard quickRules.contains(where: { $0.id == quickRule.id }) else { return }
        quickRules.removeAll { $0.id == quickRule.id }
        rules.append(quickRule)
        save()
        pushRules()
    }

    func hasRule(for bundleID: String) -> Bool { allRules.contains { $0.bundleID == bundleID } }
    func isQuick(_ rule: Rule) -> Bool { quickRules.contains { $0.id == rule.id } }

    /// Rules currently in charge.
    func isActive(_ rule: Rule) -> Bool { decision.causes.contains { $0.id == rule.id } }

    // MARK: Engine

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Keys.rules)
        }
    }

    private func pushRules(activatingNow: Set<Rule.ID> = []) {
        engine.setRules(isEnabled ? allRules : [], snapshot: watcher.snapshot, now: Self.now, activatingNow: activatingNow)
        publish()
        scheduleNext()
    }

    private func update(_ snapshot: AppSnapshot) {
        frontmost = snapshot.frontmost
        // Quick rules end with their app.
        let ended = quickRules.filter { !snapshot.running.contains($0.bundleID) }
        if !ended.isEmpty {
            quickRules.removeAll { rule in ended.contains { $0.id == rule.id } }
            engine.setRules(isEnabled ? allRules : [], snapshot: snapshot, now: Self.now)
        } else {
            engine.update(snapshot, now: Self.now)
        }
        publish()
        scheduleNext()
    }

    private func publish() {
        isWaiting = engine.isWaiting
        let next = engine.decision
        guard next != decision else { return }
        let holdChanged = next.hold != decision.hold
        decision = next
        if holdChanged { session.setRuleHold(next.hold) }
    }

    /// Sleeps until the next debounce deadline, then lets the engine catch up.
    private func scheduleNext() {
        timer?.cancel()
        guard let deadline = engine.nextDeadline else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline - Self.now)))
            guard !Task.isCancelled, let self else { return }
            engine.advance(to: Self.now)
            publish()
            scheduleNext()
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
