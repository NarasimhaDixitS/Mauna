import Testing
import Foundation

@Suite("Quiet shortcut")
struct QuietShortcutTests {

    @Test("First press quiets the way you chose")
    func firstPressQuiets() {
        #expect(QuietShortcut.action(mode: .pause, manual: .none, rule: .none) == .quiet(.paused))
        #expect(QuietShortcut.action(mode: .lower, manual: .none, rule: .none) == .quiet(.ducked))
    }

    @Test("Second press restores your own quiet")
    func secondPressRestores() {
        #expect(QuietShortcut.action(mode: .pause, manual: .paused, rule: .none) == .restore)
        #expect(QuietShortcut.action(mode: .lower, manual: .ducked, rule: .none) == .restore)
    }

    @Test("Restore still works when a rule fired on top of your quiet")
    func restoreUnderRule() {
        // You lowered it, then TextEdit paused it. Pressing again clears yours; TextEdit stays in charge.
        #expect(QuietShortcut.action(mode: .lower, manual: .ducked, rule: .paused) == .restore)
    }

    @Test("A rule already holding the music: still paused for it")
    func ruleInCharge() {
        #expect(QuietShortcut.action(mode: .pause, manual: .none, rule: .paused) == .stillHeld)
        #expect(QuietShortcut.action(mode: .lower, manual: .none, rule: .paused) == .stillHeld)
        #expect(QuietShortcut.action(mode: .lower, manual: .none, rule: .ducked) == .stillHeld)
    }

    @Test("A rule only lowered it and you pause: pause on top")
    func pauseOnTopOfDuck() {
        #expect(QuietShortcut.action(mode: .pause, manual: .none, rule: .ducked) == .quiet(.paused))
    }

    @Test("Presses closer than 300 ms are ignored")
    func doublePress() {
        var filter = QuietShortcut.PressFilter(minimumGap: 0.3)
        let accepted = [10.0, 10.1, 10.29, 10.3, 12].map { filter.accept(at: $0) }
        #expect(accepted == [true, false, false, true, true])
    }

    @Test("The effective hold is the stronger of yours and the rules'")
    func strongerWins() {
        #expect(max(Hold.ducked, Hold.paused) == .paused)
        #expect(max(Hold.none, Hold.ducked) == .ducked)
    }
}
