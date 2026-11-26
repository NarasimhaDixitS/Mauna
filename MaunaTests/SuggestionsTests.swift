import Testing

@Suite("Onboarding suggestions")
struct SuggestionsTests {
    private func app(_ id: String, _ name: String, _ category: String? = nil) -> InstalledApp {
        InstalledApp(bundleID: id, name: name, category: category)
    }

    @Test("Only installed apps, grouped in order, each with its suggested rule")
    func groups() {
        let result = Suggestions.suggest(from: [
            app("com.apple.dt.Xcode", "Xcode"),
            app("us.zoom.xos", "zoom.us"),
            app("com.apple.QuickTimePlayerX", "QuickTime Player"),
            app("com.example.notes", "Some Notes App"),
        ])
        #expect(result.map(\.group) == [.calls, .watching, .focus])
        let zoom = result[0].items[0]
        #expect(zoom.trigger == .usingMicOrSound && zoom.action == .paused)
        let xcode = result[2].items[0]
        #expect(xcode.trigger == .inFront && xcode.action == .ducked)
    }

    @Test("Versioned bundle IDs match by prefix")
    func prefix() {
        let result = Suggestions.suggest(from: [app("com.adobe.PremierePro.24", "Adobe Premiere Pro 2024")])
        #expect(result.first?.group == .creating)
    }

    @Test("Games are found by category, capped")
    func games() {
        let many = (0..<10).map { app("com.example.game\($0)", "Game \($0)", "public.app-category.action-games") }
        let result = Suggestions.suggest(from: many)
        #expect(result.first?.group == .games)
        #expect(result.first?.items.count == Suggestions.maxGames)
        #expect(result.first?.items.first?.trigger == .running)
    }

    @Test("Calls, Watching and Games start ticked; the rest don't")
    func ticked() {
        let result = Suggestions.suggest(from: [
            app("us.zoom.xos", "zoom.us"),
            app("com.apple.TV", "TV"),
            app("com.apple.iWork.Keynote", "Keynote"),
            app("com.figma.Desktop", "Figma"),
        ])
        #expect(Suggestions.initiallyTicked(result) == ["us.zoom.xos", "com.apple.TV"])
    }

    @Test("An app found twice appears once")
    func duplicates() {
        let result = Suggestions.suggest(from: [app("com.apple.TV", "TV"), app("com.apple.TV", "TV")])
        #expect(result.first?.items.count == 1)
    }
}

@Suite("Onboarding suggestions, edge cases")
struct SuggestionsEdgeTests {
    @Test("Versions of one app collapse into one row, newest named")
    func versions() {
        let result = Suggestions.suggest(from: [
            InstalledApp(bundleID: "com.adobe.PremierePro.23", name: "Adobe Premiere Pro 2023"),
            InstalledApp(bundleID: "com.adobe.PremierePro.25", name: "Adobe Premiere Pro 2025"),
            InstalledApp(bundleID: "com.adobe.PremierePro.24", name: "Adobe Premiere Pro 2024"),
        ])
        let row = result.first?.items
        #expect(row?.count == 1)
        #expect(row?.first?.app.name == "Adobe Premiere Pro 2025")
        #expect(Set(row?.first?.rules.map(\.bundleID) ?? []) == ["com.adobe.PremierePro.23", "com.adobe.PremierePro.24", "com.adobe.PremierePro.25"])
    }

    @Test("Game launchers are never suggested")
    func launchers() {
        let result = Suggestions.suggest(from: [
            InstalledApp(bundleID: "com.apple.games", name: "Games", category: "public.app-category.games"),
            InstalledApp(bundleID: "com.apple.Chess", name: "Chess", category: "public.app-category.board-games"),
        ])
        #expect(result.first?.items.map(\.app.name) == ["Chess"])
    }
}
