import Foundation

/// When a quiet app quiets the music. The three trigger names are fixed (DESIGN.md › Voice).
nonisolated enum Trigger: String, Codable, CaseIterable, Sendable {
    /// Pauses while the app is the active app. Xcode, Figma, writing apps, video players.
    case inFront
    /// "In a call": pauses while the app is using the microphone. Zoom, Teams, FaceTime, Meet in Chrome.
    /// (Stored as "usingMicOrSound", its original name, so saved rules keep loading.)
    case usingMicOrSound
    /// Pauses from launch until it quits. Games, full-screen tools.
    case running

    var name: String {
        switch self {
        case .inFront:         "In front"
        case .usingMicOrSound: "In a call"
        case .running:         "Running"
        }
    }

    /// Short badge label in the popover rules list.
    var badge: String {
        switch self {
        case .inFront:         "Front"
        case .usingMicOrSound: "Call"
        case .running:         "Running"
        }
    }
}

/// What a rule, or the quiet shortcut, does to the music. Pause outranks duck.
nonisolated enum Hold: Int, Comparable, Codable, Sendable {
    case none = 0
    case ducked = 1
    case paused = 2

    static func < (lhs: Hold, rhs: Hold) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One quiet app.
nonisolated struct Rule: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var trigger: Trigger
    /// `.paused` or `.ducked`.
    var action: Hold = .paused
    var isEnabled = true
}

extension Rule {
    /// The triggers Mauna offers.
    static let availableTriggers: [Trigger] = [.inFront, .usingMicOrSound, .running]

    /// Apps you make calls in. They get "In a call": they sit open all day, but quiet music only on a call.
    nonisolated static let callApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.webex.meetingmanager",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.skype.skype", "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
    ]

    /// Spec › Smart default: call apps get "In a call", games "Running", everything else "In front".
    static func suggestedTrigger(bundleID: String, category: String?) -> Trigger {
        if callApps.contains(bundleID) { return .usingMicOrSound }
        if let category, category.contains("games") { return .running }
        return .inFront
    }

    /// One plain sentence for Settings › Rules: "Pauses while Xcode is in front".
    var summary: String {
        switch (trigger, action) {
        case (.inFront, .ducked):         "Lowers music while \(appName) is in front"
        case (.inFront, _):               "Pauses while \(appName) is in front"
        case (.running, .ducked):         "Lowers music from launch until it quits"
        case (.running, _):               "Pauses from launch until it quits"
        case (.usingMicOrSound, .ducked): "Lowers music during calls, even if you switch apps"
        case (.usingMicOrSound, _):       "Pauses during calls, even if you switch apps"
        }
    }
}

/// The facts the rule engine needs about other apps.
nonisolated struct AppSnapshot: Equatable, Sendable {
    var frontmost: String?
    var running: Set<String> = []
    /// Apps in a call right now: using the mic, or playing sound for a while (see `inCall`).
    var usingAudio: Set<String> = []
}

extension AppSnapshot {
    /// System services that use the mic on an app's behalf: FaceTime's call audio runs in avconferenced.
    static let micServices: [String: String] = [
        "com.apple.avconferenced": "com.apple.FaceTime",
    ]

    /// The apps a mic-using process counts for: itself, the app a helper belongs to
    /// ("com.google.Chrome.helper" counts for Chrome), or the app a system service works for.
    static func micOwners(of bundleID: String, running: [String]) -> Set<String> {
        var owners: Set<String> = [bundleID]
        if let app = micServices[bundleID] { owners.insert(app) }
        for app in running where bundleID.hasPrefix(app + ".") { owners.insert(app) }
        return owners
    }

    /// Apps whose sound alone never means a call: browsers and music players, whose sound is usually
    /// music (YouTube Music in Chrome must never count as Chrome being in a call). The mic still counts.
    static let soundIsUsuallyMusic: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.spotify.client", "com.apple.Music",
    ]

    /// Who's in a call right now:
    /// - every app using the mic, and
    /// - every app that has been playing sound for at least `minimumSound` seconds. A muted call keeps
    ///   playing the other people (Zoom lets go of the mic while you're muted); a notification ding
    ///   is over in a second or two.
    static func inCall(mic: Set<String>, soundSince: [String: TimeInterval], now: TimeInterval,
                       minimumSound: TimeInterval = AudioTiming.shortSoundIgnore) -> Set<String> {
        var apps = mic
        for (app, since) in soundSince where now - since >= minimumSound && !soundIsUsuallyMusic.contains(app) {
            apps.insert(app)
        }
        return apps
    }

    /// Call apps whose old "Running" rules should become "In a call" (one-time, see RuleCoordinator).
    static func callRulesToMove(_ rules: [Rule]) -> [Rule.ID] {
        rules.filter { Rule.callApps.contains($0.bundleID) && $0.trigger == .running }.map(\.id)
    }
}
