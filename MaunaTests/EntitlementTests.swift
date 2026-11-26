import Foundation
import Testing

struct EntitlementTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    private func rule(_ name: String, _ trigger: Trigger = .inFront, _ action: Hold = .paused, enabled: Bool = true) -> Rule {
        var rule = Rule(bundleID: "test.\(name)", appName: name, trigger: trigger, action: action)
        rule.isEnabled = enabled
        return rule
    }

    // MARK: Plan

    @Test func proBeatsEverything() {
        #expect(Plan.current(ownsPro: true, trialStartedAt: now, now: now) == .pro)
    }

    @Test func trialLastsFourteenDays() {
        let started = now.addingTimeInterval(-13 * day)
        #expect(Plan.current(ownsPro: false, trialStartedAt: started, now: now).unlocksPro)
        let expired = now.addingTimeInterval(-14 * day - 1)
        #expect(Plan.current(ownsPro: false, trialStartedAt: expired, now: now) == .free)
    }

    @Test func noTrialIsFree() {
        #expect(Plan.current(ownsPro: false, trialStartedAt: nil, now: now) == .free)
    }

    @Test func daysLeftRoundsUp() {
        let plan = Plan.trial(endsAt: now.addingTimeInterval(8.2 * day))
        #expect(plan.trialDaysLeft(now: now) == 9)
        let lastHours = Plan.trial(endsAt: now.addingTimeInterval(3600))
        #expect(lastHours.trialDaysLeft(now: now) == 1)
        #expect(Plan.pro.trialDaysLeft(now: now) == nil)
    }

    // MARK: Resting rules

    @Test func proAndTrialRestNothing() {
        let rules = (0..<9).map { rule("app\($0)", .running, .ducked) }
        #expect(Entitlement.resting(rules, plan: .pro).isEmpty)
        #expect(Entitlement.resting(rules, plan: .trial(endsAt: now)).isEmpty)
    }

    @Test func freeRunsTheFirstTwoSimpleRules() {
        let rules = [rule("a"), rule("b"), rule("c"), rule("d")]
        let resting = Entitlement.resting(rules, plan: .free)
        #expect(resting == [rules[2].id, rules[3].id])
    }

    @Test func proOnlyRulesRestAndDontUseUpTheFreeSlots() {
        let zoom = rule("zoom", .running)
        let notes = rule("notes", .inFront, .ducked)
        let xcode = rule("xcode")
        let chess = rule("chess")
        let resting = Entitlement.resting([zoom, notes, xcode, chess], plan: .free)
        #expect(resting == [zoom.id, notes.id])   // xcode and chess run
        #expect(Entitlement.restReason(for: zoom) == .everyTrigger)
        #expect(Entitlement.restReason(for: notes) == .lower)
        #expect(Entitlement.restReason(for: rule("third")) == .moreRules)
    }

    @Test func switchedOffRulesDontCount() {
        let off = rule("off", enabled: false)
        let rules = [off, rule("a"), rule("b")]
        #expect(Entitlement.resting(rules, plan: .free).isEmpty)
    }

    @Test func addingOnFree() {
        #expect(Entitlement.canAddOnFree([rule("a")]))
        #expect(!Entitlement.canAddOnFree([rule("a"), rule("b")]))
        #expect(Entitlement.canAddOnFree([rule("a"), rule("z", .running)]))
    }
}
