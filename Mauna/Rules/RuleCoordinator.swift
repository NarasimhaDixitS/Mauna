import Foundation
import Observation

/// Connects the app watcher to the rule engine, and the engine's decision to the player.
@Observable
final class RuleCoordinator {
    private(set) var decision = RuleEngine.Decision()
    /// True while a change is waiting out the debounce. The popover shows it.
    private(set) var isWaiting = false
    /// True while nobody is at the Mac. Rules hold still.
    private(set) var isAway = false
    private(set) var rules: [Rule]

    @ObservationIgnored private var engine: RuleEngine
    @ObservationIgnored private let watcher = AppWatcher()
    @ObservationIgnored private let session: PlayerSession
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(session: PlayerSession, rules: [Rule]) {
        self.session = session
        self.rules = rules
        self.engine = RuleEngine(rules: rules)

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
        update(watcher.snapshot)
    }

    func setRules(_ newRules: [Rule]) {
        rules = newRules
        engine.setRules(newRules, snapshot: watcher.snapshot, now: Self.now)
        publish()
        scheduleNext()
    }

    /// Rules currently in charge.
    func isActive(_ rule: Rule) -> Bool { decision.causes.contains { $0.id == rule.id } }

    private func update(_ snapshot: AppSnapshot) {
        engine.update(snapshot, now: Self.now)
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

extension Rule {
    /// Phase 2 test rules, until Settings › Rules arrives in Phase 4.
    static let phase2Samples: [Rule] = [
        Rule(bundleID: "com.apple.TextEdit", appName: "TextEdit", trigger: .inFront, action: .paused),
        Rule(bundleID: "com.apple.Notes", appName: "Notes", trigger: .inFront, action: .ducked),
        Rule(bundleID: "com.apple.Chess", appName: "Chess", trigger: .running, action: .paused),
    ]
}
