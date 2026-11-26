import Foundation

/// What you've unlocked. Pure: no StoreKit, so the rules for Free, the trial and Pro are tested directly.
nonisolated enum Plan: Equatable, Sendable {
    case free
    /// Everything unlocked until `endsAt`.
    case trial(endsAt: Date)
    case pro

    /// Pro features are on: bought, or during the trial.
    var unlocksPro: Bool { self != .free }

    /// The plan from what's been bought. The trial is a free in-app purchase: 7 days from when you took it.
    static func current(ownsPro: Bool, trialStartedAt: Date?, now: Date) -> Plan {
        if ownsPro { return .pro }
        if let start = trialStartedAt {
            let end = start.addingTimeInterval(Entitlement.trialLength)
            if now < end { return .trial(endsAt: end) }
        }
        return .free
    }

    /// "9 days left", for the trial. Rounds up: on the last afternoon it's still "1 day left".
    func trialDaysLeft(now: Date) -> Int? {
        guard case .trial(let end) = self else { return nil }
        return max(1, Int((end.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

/// What Pro unlocks at v1 (docs/ROADMAP.md › Pro at launch).
nonisolated enum ProFeature: String, Sendable, CaseIterable, Identifiable {
    case moreRules, everyTrigger, lower, youTubeMusic, customFade
    var id: String { rawValue }
}

nonisolated enum Entitlement {
    /// Free: two rules, "In front", Pause.
    static let freeRuleLimit = 2
    static let trialLength: TimeInterval = 7 * 86_400

    /// A rule Free can run: "In front", Pause.
    static func fitsFree(_ rule: Rule) -> Bool {
        rule.trigger == .inFront && rule.action == .paused
    }

    /// Rules that rest on this plan: never deleted, just not acting, with a note saying why.
    /// On Free, the first two enabled rules that fit Free run; every other enabled rule rests.
    /// So a trial that ends leaves your first two simple rules working, and nothing is lost.
    static func resting(_ rules: [Rule], plan: Plan) -> Set<Rule.ID> {
        guard !plan.unlocksPro else { return [] }
        var running = 0
        var resting: Set<Rule.ID> = []
        for rule in rules where rule.isEnabled {
            if fitsFree(rule) && running < freeRuleLimit {
                running += 1
            } else {
                resting.insert(rule.id)
            }
        }
        return resting
    }

    /// Why a resting rule rests, in a few words: the Pro feature it needs.
    static func restReason(for rule: Rule) -> ProFeature {
        if rule.trigger != .inFront { return .everyTrigger }
        if rule.action != .paused { return .lower }
        return .moreRules
    }

    /// Whether a new rule can be added on Free without resting.
    static func canAddOnFree(_ rules: [Rule]) -> Bool {
        rules.filter { $0.isEnabled && fitsFree($0) }.count < freeRuleLimit
    }
}
