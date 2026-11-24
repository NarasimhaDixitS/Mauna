import Foundation

/// When a quiet app quiets the music. The three trigger names are fixed (DESIGN.md › Voice).
nonisolated enum Trigger: String, Codable, CaseIterable, Sendable {
    /// Pauses while the app is the active app. Xcode, Figma, writing apps, video players.
    case inFront
    /// Pauses while the app uses the mic or plays sound. Zoom, Teams, Meet. Arrives in v1.1.
    case usingMicOrSound
    /// Pauses from launch until it quits. Games, full-screen tools.
    case running

    var name: String {
        switch self {
        case .inFront:         "In front"
        case .usingMicOrSound: "Using mic or sound"
        case .running:         "Running"
        }
    }

    /// Short badge label in the popover rules list.
    var badge: String {
        switch self {
        case .inFront:         "Front"
        case .usingMicOrSound: "Mic"
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

/// The facts the rule engine needs about other apps.
nonisolated struct AppSnapshot: Equatable, Sendable {
    var frontmost: String?
    var running: Set<String> = []
    /// Apps using the mic or playing sound (v1.1).
    var usingAudio: Set<String> = []
}
