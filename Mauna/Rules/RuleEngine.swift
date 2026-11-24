import Foundation

/// Decides what should happen to the music, from the rules and what other apps are doing.
/// Pure and clock-free: callers pass `now` (seconds), so tests can drive time.
///
/// Behaviour (spec › Edge cases):
/// - Debounce: a rule only turns on or off after its trigger has held for `debounce` seconds,
///   so quick ⌘Tab switches never flicker the music.
/// - Two quiet apps at once: every active rule is tracked; music returns only when none are left.
/// - The user pressed play during a pause: the active rules are overridden until each one's trigger ends.
/// - Pause outranks duck.
/// - Away (screen saver, locked, asleep): nothing changes until you're back, then changes wait a fresh debounce.
nonisolated struct RuleEngine: Sendable {
    struct Decision: Equatable, Sendable {
        var hold: Hold = .none
        /// Rules currently in charge, strongest first, then in rule order.
        var causes: [Rule] = []
    }

    var debounce: TimeInterval = AudioTiming.debounce

    private(set) var rules: [Rule]
    /// Rules whose trigger has held long enough.
    private(set) var active: Set<Rule.ID> = []
    /// Active rules the user overrode by pressing play.
    private(set) var overridden: Set<Rule.ID> = []
    /// Rules whose trigger is on right now, before debounce.
    private var triggered: Set<Rule.ID> = []
    /// When a rule will flip to match `triggered`.
    private var pending: [Rule.ID: TimeInterval] = [:]
    /// True while nobody is at the Mac. Time stops for the rules.
    private(set) var isAway = false

    init(rules: [Rule], debounce: TimeInterval = AudioTiming.debounce) {
        self.rules = rules
        self.debounce = debounce
    }

    // MARK: Inputs

    /// New facts about other apps.
    mutating func update(_ snapshot: AppSnapshot, now: TimeInterval) {
        triggered = Set(rules.filter { $0.isEnabled && Self.isTriggered($0, by: snapshot) }.map(\.id))
        for rule in rules {
            let wanted = triggered.contains(rule.id)
            if wanted == active.contains(rule.id) {
                pending[rule.id] = nil                       // flipped back in time: nothing happens
            } else if pending[rule.id] == nil {
                pending[rule.id] = now + debounce
            }
        }
        advance(to: now)
    }

    /// Lets time pass. Call at `nextDeadline`.
    mutating func advance(to now: TimeInterval) {
        guard !isAway else { return }
        for (id, deadline) in pending where deadline <= now {
            pending[id] = nil
            if triggered.contains(id) {
                active.insert(id)
            } else {
                active.remove(id)
                overridden.remove(id)                        // the override lasts until the trigger ends
            }
        }
    }

    /// The screen saver started, the screen locked or the Mac slept (true), or the user is back (false).
    /// Never resume, or pause, music for an empty room.
    mutating func setAway(_ away: Bool, now: TimeInterval) {
        guard away != isAway else { return }
        isAway = away
        if !away {
            // Whatever changed while away waits out a full debounce from now.
            for id in pending.keys { pending[id] = now + debounce }
        }
    }

    /// The user pressed play while Mauna had paused the music.
    mutating func userOverrode() {
        overridden.formUnion(active)
    }

    /// Replaces the rule list, keeping the state of rules that still exist.
    /// Rules in `activatingNow` skip the debounce: you just asked for them by hand ("Pause until Safari quits").
    mutating func setRules(_ newRules: [Rule], snapshot: AppSnapshot, now: TimeInterval, activatingNow: Set<Rule.ID> = []) {
        let ids = Set(newRules.map(\.id))
        rules = newRules
        active.formIntersection(ids)
        overridden.formIntersection(ids)
        pending = pending.filter { ids.contains($0.key) }
        update(snapshot, now: now)
        guard !isAway else { return }
        for id in activatingNow where triggered.contains(id) && pending[id] != nil {
            pending[id] = nil
            active.insert(id)
        }
    }

    // MARK: Outputs

    var decision: Decision {
        let inCharge = rules.filter { active.contains($0.id) && !overridden.contains($0.id) }
        let hold = inCharge.map(\.action).max() ?? .none
        let causes = inCharge.filter { $0.action == hold } + inCharge.filter { $0.action != hold }
        return Decision(hold: hold, causes: causes)
    }

    /// When the next debounced change is due, if any.
    var nextDeadline: TimeInterval? { isAway ? nil : pending.values.min() }

    /// True while a change is waiting out its debounce.
    var isWaiting: Bool { !isAway && !pending.isEmpty }

    static func isTriggered(_ rule: Rule, by snapshot: AppSnapshot) -> Bool {
        switch rule.trigger {
        case .inFront:         snapshot.frontmost == rule.bundleID
        case .running:         snapshot.running.contains(rule.bundleID)
        case .usingMicOrSound: snapshot.usingAudio.contains(rule.bundleID)
        }
    }
}
