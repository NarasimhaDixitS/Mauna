import Foundation

/// Onboarding step 2: quiet apps Mauna suggests, from the apps installed on this Mac.
/// Only installed apps are shown. Calls, Watching and Games start ticked; the rest are personal, so they don't.
nonisolated enum SuggestionGroup: String, CaseIterable, Identifiable, Sendable {
    case calls, watching, games, creating, presenting, focus

    var id: Self { self }

    var title: String {
        switch self {
        case .calls:      "Calls"
        case .watching:   "Watching"
        case .games:      "Games"
        case .creating:   "Creating"
        case .presenting: "Presenting"
        case .focus:      "Focus"
        }
    }

    var reason: String {
        switch self {
        case .calls:      "Music pauses while the call app is open."
        case .watching:   "Your film or video plays on its own."
        case .games:      "Games bring their own sound."
        case .creating:   "Editors and music apps play their own audio."
        case .presenting: "Silence while you present."
        case .focus:      "Soft music keeps going while you work."
        }
    }

    var symbol: String {
        switch self {
        case .calls:      "phone.fill"
        case .watching:   "play.rectangle.fill"
        case .games:      "gamecontroller.fill"
        case .creating:   "film.stack.fill"
        case .presenting: "rectangle.on.rectangle.angled.fill"
        case .focus:      "scope"
        }
    }

    /// Almost nobody wants music during a call, a film or a game.
    var startsTicked: Bool { self == .calls || self == .watching || self == .games }
}

/// An app found on this Mac.
nonisolated struct InstalledApp: Hashable, Sendable {
    var bundleID: String
    var name: String
    var category: String?
    /// Where the app lives, for its icon.
    var path: String? = nil
}

nonisolated struct Suggestion: Identifiable, Hashable, Sendable {
    var app: InstalledApp
    var group: SuggestionGroup
    var trigger: Trigger
    var action: Hold
    /// Older versions of the same app (Premiere Pro 2023, 2024…). Each gets the same rule.
    var otherVersions: [String] = []
    var id: String { app.bundleID }

    var rules: [Rule] {
        ([app.bundleID] + otherVersions).map { Rule(bundleID: $0, appName: app.name, trigger: trigger, action: action) }
    }
}

nonisolated enum Suggestions {
    private struct Entry {
        /// A bundle ID, or a prefix ending in "*" for apps whose ID carries a version (Adobe, Resolve).
        let match: String
        let group: SuggestionGroup
        let trigger: Trigger
        let action: Hold

        func matches(_ bundleID: String) -> Bool {
            match.hasSuffix("*") ? bundleID.hasPrefix(String(match.dropLast())) : bundleID == match
        }
    }

    private static let catalog: [Entry] = {
        func add(_ group: SuggestionGroup, _ trigger: Trigger, _ action: Hold, _ ids: [String]) -> [Entry] {
            ids.map { Entry(match: $0, group: group, trigger: trigger, action: action) }
        }
        // "In a call": these sit open all day, but quiet music only while a call has the mic.
        return add(.calls, .usingMicOrSound, .paused, [
            "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime",
            "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.skype.skype",
            "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        ])
        + add(.watching, .inFront, .paused, [
            "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "com.apple.TV", "com.firecore.infuse",
        ])
        + add(.creating, .inFront, .paused, [
            "com.apple.FinalCut", "com.apple.motionapp", "com.apple.iMovieApp", "com.apple.logic10", "com.apple.garageband10",
            "com.blackmagic-design.DaVinciResolve*", "com.adobe.PremierePro*", "com.adobe.AfterEffects*", "com.ableton.live*",
        ])
        + add(.presenting, .inFront, .paused, ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint"])
        + add(.focus, .inFront, .ducked, [
            "com.apple.dt.Xcode", "com.figma.Desktop", "notion.id", "md.obsidian", "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92", "com.apple.iWork.Pages", "com.microsoft.Word",
        ])
    }()

    /// At most this many games, so one big library doesn't swamp the list.
    static let maxGames = 6

    /// Launchers stay open for hours, so "Running" would silence music the whole time.
    static let neverSuggest: Set<String> = ["com.apple.games", "com.valvesoftware.steam", "com.epicgames.EpicGamesLauncher"]

    /// Suggestions for the installed apps, grouped in display order. Each app appears once.
    static func suggest(from installed: [InstalledApp]) -> [(group: SuggestionGroup, items: [Suggestion])] {
        var byGroup: [SuggestionGroup: [Suggestion]] = [:]
        var seen: Set<String> = []
        /// Versioned apps collapse into one row, named after the newest version.
        var versioned: [String: (group: SuggestionGroup, index: Int)] = [:]
        // By name: within a versioned app, "2023" comes before "2025", so the newest ends up naming the row.
        for app in installed.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            guard seen.insert(app.bundleID).inserted, !neverSuggest.contains(app.bundleID) else { continue }
            if let entry = catalog.first(where: { $0.matches(app.bundleID) }) {
                if entry.match.hasSuffix("*"), let existing = versioned[entry.match] {
                    // A newer version sorts later: it takes over the row, the older one rides along.
                    var row = byGroup[existing.group]![existing.index]
                    row.otherVersions.append(row.app.bundleID)
                    row.app = app
                    byGroup[existing.group]![existing.index] = row
                    continue
                }
                byGroup[entry.group, default: []].append(Suggestion(app: app, group: entry.group, trigger: entry.trigger, action: entry.action))
                if entry.match.hasSuffix("*") { versioned[entry.match] = (entry.group, byGroup[entry.group]!.count - 1) }
            } else if let category = app.category, category.contains("games"), byGroup[.games, default: []].count < maxGames {
                byGroup[.games, default: []].append(Suggestion(app: app, group: .games, trigger: .running, action: .paused))
            }
        }
        return SuggestionGroup.allCases.compactMap { group in
            guard let items = byGroup[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    /// Settings › Rules sections: what kind of app this is, from Mauna's own list, then the app's
    /// App Store category. nil means "Other".
    static func kind(of bundleID: String, category: String?) -> SuggestionGroup? {
        if let entry = catalog.first(where: { $0.matches(bundleID) }) { return entry.group }
        if Rule.callApps.contains(bundleID) { return .calls }
        guard let category else { return nil }
        let name = category.replacingOccurrences(of: "public.app-category.", with: "")
        if name.contains("games") { return .games }
        switch name {
        case "video", "entertainment": return .watching
        case "music", "photography", "graphics-design": return .creating
        case "developer-tools", "productivity", "business", "education", "reference": return .focus
        default: return nil
        }
    }

    /// What starts ticked.
    static func initiallyTicked(_ groups: [(group: SuggestionGroup, items: [Suggestion])]) -> Set<String> {
        Set(groups.filter(\.group.startsTicked).flatMap { $0.items.map(\.id) })
    }
}
