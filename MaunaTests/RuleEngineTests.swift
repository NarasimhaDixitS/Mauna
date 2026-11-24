import Testing
import Foundation

// The rule engine is compiled straight into this test bundle (see project.yml),
// so these tests run without launching Mauna or touching any music player.

private let xcode = Rule(bundleID: "com.apple.dt.Xcode", appName: "Xcode", trigger: .inFront, action: .ducked)
private let zoom  = Rule(bundleID: "us.zoom.xos", appName: "Zoom", trigger: .running, action: .paused)
private let notes = Rule(bundleID: "com.apple.Notes", appName: "Notes", trigger: .inFront, action: .paused)

private func front(_ bundleID: String?, running: Set<String> = []) -> AppSnapshot {
    AppSnapshot(frontmost: bundleID, running: running)
}

@Suite("Rule engine")
struct RuleEngineTests {

    @Test("In front pauses only after the debounce")
    func inFrontDebounce() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        #expect(engine.decision.hold == .none)
        #expect(engine.nextDeadline == 1.5)

        engine.advance(to: 1.4)
        #expect(engine.decision.hold == .none)

        engine.advance(to: 1.5)
        #expect(engine.decision.hold == .paused)
        #expect(engine.decision.causes.map(\.appName) == ["Notes"])
    }

    @Test("A quick ⌘Tab through a quiet app changes nothing")
    func quickSwitchDoesNotFlicker() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.update(front("com.apple.Safari"), now: 0.8)
        #expect(engine.nextDeadline == nil)
        engine.advance(to: 10)
        #expect(engine.decision.hold == .none)
    }

    @Test("Leaving the app resumes only after the debounce")
    func resumeDebounce() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 2)
        engine.update(front("com.apple.Safari"), now: 5)
        #expect(engine.decision.hold == .paused)
        engine.advance(to: 6.5)
        #expect(engine.decision.hold == .none)
    }

    @Test("A quick look away and back keeps the music paused")
    func briefReturnKeepsPause() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 2)
        engine.update(front("com.apple.Safari"), now: 5)
        engine.update(front("com.apple.Notes"), now: 5.5)
        engine.advance(to: 20)
        #expect(engine.decision.hold == .paused)
    }

    @Test("Two quiet apps: music returns only when both have ended")
    func twoRules() {
        var engine = RuleEngine(rules: [notes, zoom], debounce: 1.5)
        engine.update(front("com.apple.Notes", running: ["us.zoom.xos"]), now: 0)
        engine.advance(to: 2)
        #expect(Set(engine.decision.causes.map(\.appName)) == ["Notes", "Zoom"])

        engine.update(front("com.apple.Safari", running: ["us.zoom.xos"]), now: 3)
        engine.advance(to: 5)
        #expect(engine.decision.hold == .paused)
        #expect(engine.decision.causes.map(\.appName) == ["Zoom"])

        engine.update(front("com.apple.Safari"), now: 6)
        engine.advance(to: 8)
        #expect(engine.decision.hold == .none)
    }

    @Test("Pause outranks duck, and duck takes over when the pause ends")
    func pauseOutranksDuck() {
        var engine = RuleEngine(rules: [xcode, zoom], debounce: 1.5)
        engine.update(front("com.apple.dt.Xcode"), now: 0)
        engine.advance(to: 2)
        #expect(engine.decision.hold == .ducked)

        engine.update(front("com.apple.dt.Xcode", running: ["us.zoom.xos"]), now: 3)
        engine.advance(to: 5)
        #expect(engine.decision.hold == .paused)
        #expect(engine.decision.causes.first?.appName == "Zoom")

        engine.update(front("com.apple.dt.Xcode"), now: 6)
        engine.advance(to: 8)
        #expect(engine.decision.hold == .ducked)
    }

    @Test("Pressing play overrides active rules until their trigger ends")
    func userOverride() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 2)
        engine.userOverrode()
        #expect(engine.decision.hold == .none)

        // Still in Notes: stays overridden.
        engine.update(front("com.apple.Notes"), now: 10)
        engine.advance(to: 20)
        #expect(engine.decision.hold == .none)

        // Leave, then come back: the rule applies again.
        engine.update(front("com.apple.Safari"), now: 30)
        engine.advance(to: 32)
        engine.update(front("com.apple.Notes"), now: 40)
        engine.advance(to: 42)
        #expect(engine.decision.hold == .paused)
    }

    @Test("An override doesn't block a rule that starts later")
    func overrideIsPerRule() {
        var engine = RuleEngine(rules: [notes, zoom], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 2)
        engine.userOverrode()
        engine.update(front("com.apple.Notes", running: ["us.zoom.xos"]), now: 5)
        engine.advance(to: 7)
        #expect(engine.decision.hold == .paused)
        #expect(engine.decision.causes.map(\.appName) == ["Zoom"])
    }

    @Test("Running pauses from launch until quit")
    func runningTrigger() {
        var engine = RuleEngine(rules: [zoom], debounce: 1.5)
        engine.update(front("com.apple.Safari", running: ["us.zoom.xos"]), now: 0)
        engine.advance(to: 1.5)
        #expect(engine.decision.hold == .paused)
        engine.update(front("us.zoom.xos", running: ["us.zoom.xos"]), now: 3)
        engine.update(front("com.apple.Safari", running: ["us.zoom.xos"]), now: 4)
        engine.advance(to: 10)
        #expect(engine.decision.hold == .paused)
        engine.update(front("com.apple.Safari"), now: 11)
        engine.advance(to: 12.5)
        #expect(engine.decision.hold == .none)
    }

    @Test("Disabled rules are ignored")
    func disabledRule() {
        var off = notes
        off.isEnabled = false
        var engine = RuleEngine(rules: [off], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 5)
        #expect(engine.decision.hold == .none)
    }

    @Test("Removing an active rule releases the music")
    func removingRule() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        let snapshot = front("com.apple.Notes")
        engine.update(snapshot, now: 0)
        engine.advance(to: 2)
        engine.setRules([], snapshot: snapshot, now: 3)
        #expect(engine.decision.hold == .none)
    }

    @Test("Away: an app quitting doesn't resume music for an empty room")
    func awayFreezes() {
        var engine = RuleEngine(rules: [zoom], debounce: 1.5)
        engine.update(front(nil, running: ["us.zoom.xos"]), now: 0)
        engine.advance(to: 2)
        #expect(engine.decision.hold == .paused)

        engine.setAway(true, now: 10)
        engine.update(front(nil), now: 11)          // Zoom quit while you were away
        #expect(engine.nextDeadline == nil)
        engine.advance(to: 100)
        #expect(engine.decision.hold == .paused)

        engine.setAway(false, now: 200)             // back: a fresh debounce from now
        #expect(engine.nextDeadline == 201.5)
        engine.advance(to: 201)
        #expect(engine.decision.hold == .paused)
        engine.advance(to: 201.5)
        #expect(engine.decision.hold == .none)
    }

    @Test("Away: a change just before leaving waits until you're back")
    func awayResetsPendingDebounce() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 2)
        engine.update(front("com.apple.Safari"), now: 5)
        engine.setAway(true, now: 5.5)
        engine.setAway(false, now: 60)
        engine.advance(to: 60)
        #expect(engine.decision.hold == .paused)    // the old 6.5 deadline doesn't fire at once
        engine.advance(to: 61.5)
        #expect(engine.decision.hold == .none)
    }

    @Test("Away and back with nothing changed: no waiting")
    func awayNoChange() {
        var engine = RuleEngine(rules: [notes], debounce: 1.5)
        engine.update(front("com.apple.Notes"), now: 0)
        engine.advance(to: 2)
        engine.setAway(true, now: 3)
        engine.setAway(false, now: 50)
        #expect(engine.isWaiting == false)
        #expect(engine.decision.hold == .paused)
    }
}
