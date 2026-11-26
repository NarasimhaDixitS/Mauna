import Foundation
import Testing

/// "In a call": rules follow the microphone, not whether the app is open.
struct CallTriggerTests {
    let zoom = Rule(bundleID: "us.zoom.xos", appName: "zoom.us", trigger: .usingMicOrSound, action: .paused)

    @Test func openWithoutACallLeavesMusicAlone() {
        var engine = RuleEngine(rules: [zoom])
        engine.setRules([zoom], snapshot: AppSnapshot(frontmost: "us.zoom.xos", running: ["us.zoom.xos"]), now: 0)
        engine.advance(to: 10)
        #expect(engine.decision.hold == .none)
    }

    @Test func aCallPausesEvenFromAnotherApp() {
        var engine = RuleEngine(rules: [zoom])
        let inCall = AppSnapshot(frontmost: "com.apple.Notes", running: ["us.zoom.xos"], usingAudio: ["us.zoom.xos"])
        engine.setRules([zoom], snapshot: inCall, now: 0)
        engine.advance(to: 10)
        #expect(engine.decision.hold == .paused)
    }

    @Test func helpersAndServicesCountForTheirApp() {
        let running = ["com.google.Chrome", "com.microsoft.teams2", "com.apple.FaceTime"]
        #expect(AppSnapshot.micOwners(of: "com.google.Chrome.helper", running: running).contains("com.google.Chrome"))
        #expect(AppSnapshot.micOwners(of: "com.microsoft.teams2.helper", running: running).contains("com.microsoft.teams2"))
        #expect(AppSnapshot.micOwners(of: "com.apple.avconferenced", running: running).contains("com.apple.FaceTime"))
        // A different app whose ID merely starts the same way doesn't count.
        #expect(!AppSnapshot.micOwners(of: "com.google.Chromecast", running: running).contains("com.google.Chrome"))
    }

    @Test func onlyRunningCallAppsMove() {
        let zoomRunning = Rule(bundleID: "us.zoom.xos", appName: "zoom.us", trigger: .running)
        let teamsInFront = Rule(bundleID: "com.microsoft.teams2", appName: "Teams", trigger: .inFront)
        let chessRunning = Rule(bundleID: "com.apple.Chess", appName: "Chess", trigger: .running)
        #expect(AppSnapshot.callRulesToMove([zoomRunning, teamsInFront, chessRunning]) == [zoomRunning.id])
    }

    @Test func soundCountsAfterAFewSeconds() {
        // Zoom muted: no mic, but the other people are still talking.
        let sound = ["us.zoom.xos": 100.0]
        #expect(AppSnapshot.inCall(mic: [], soundSince: sound, now: 101).isEmpty)          // a ding
        #expect(AppSnapshot.inCall(mic: [], soundSince: sound, now: 104) == ["us.zoom.xos"]) // a call
    }

    @Test func browserAndPlayerSoundIsMusicNotACall() {
        let sound = ["com.google.Chrome": 0.0, "com.spotify.client": 0.0]
        #expect(AppSnapshot.inCall(mic: [], soundSince: sound, now: 60).isEmpty)
        // Meet in Chrome still counts through the mic.
        #expect(AppSnapshot.inCall(mic: ["com.google.Chrome"], soundSince: sound, now: 60) == ["com.google.Chrome"])
    }
}
