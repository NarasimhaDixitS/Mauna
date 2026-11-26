import Testing
import Foundation

@Suite("Rules you add")
struct RuleModelTests {
    private let safari = Rule(bundleID: "com.apple.Safari", appName: "Safari", trigger: .running, action: .paused)

    @Test("A rule you add by hand acts at once, without the 1.5 s wait")
    func addedRuleActsNow() {
        var engine = RuleEngine(rules: [], debounce: 1.5)
        let snapshot = AppSnapshot(frontmost: "com.apple.Safari", running: ["com.apple.Safari"])
        engine.update(snapshot, now: 0)
        engine.setRules([safari], snapshot: snapshot, now: 10, activatingNow: [safari.id])
        #expect(engine.decision.hold == .paused)
        #expect(engine.isWaiting == false)
    }

    @Test("A rule added for an app that isn't open waits for it")
    func addedRuleForClosedApp() {
        var engine = RuleEngine(rules: [], debounce: 1.5)
        let snapshot = AppSnapshot(frontmost: "com.apple.Notes", running: ["com.apple.Notes"])
        engine.setRules([safari], snapshot: snapshot, now: 0, activatingNow: [safari.id])
        #expect(engine.decision.hold == .none)
    }

    @Test("Rules restored at launch still wait out the debounce")
    func restoredRulesDebounce() {
        var engine = RuleEngine(rules: [], debounce: 1.5)
        let snapshot = AppSnapshot(frontmost: "com.apple.Safari", running: ["com.apple.Safari"])
        engine.setRules([safari], snapshot: snapshot, now: 0)
        #expect(engine.decision.hold == .none)
        engine.advance(to: 1.5)
        #expect(engine.decision.hold == .paused)
    }

    @Test("Smart default: call apps and games run, everything else is in front")
    func smartDefault() {
        #expect(Rule.suggestedTrigger(bundleID: "us.zoom.xos", category: nil) == .usingMicOrSound)
        #expect(Rule.suggestedTrigger(bundleID: "com.example.game", category: "public.app-category.action-games") == .running)
        #expect(Rule.suggestedTrigger(bundleID: "com.apple.dt.Xcode", category: "public.app-category.developer-tools") == .inFront)
        #expect(Rule.suggestedTrigger(bundleID: "com.figma.Desktop", category: nil) == .inFront)
    }

    @Test("Summaries name the app and the action")
    func summaries() {
        let xcode = Rule(bundleID: "com.apple.dt.Xcode", appName: "Xcode", trigger: .inFront, action: .ducked)
        #expect(xcode.summary == "Lowers music while Xcode is in front")
        #expect(safari.summary == "Pauses from launch until it quits")
    }

    @Test("Rules survive a save and load")
    func codable() throws {
        let rules = [safari, Rule(bundleID: "com.apple.Notes", appName: "Notes", trigger: .inFront, action: .ducked)]
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode([Rule].self, from: data) == rules)
    }
}
