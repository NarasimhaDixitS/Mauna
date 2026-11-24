import AppKit

/// Finds the apps on this Mac: /Applications (and one folder deep, for Adobe and friends),
/// Utilities, /System/Applications and ~/Applications. Reads only each app's Info.plist.
enum InstalledApps {
    static func scan() async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) { scanNow() }.value
    }

    nonisolated private static func scanNow() -> [InstalledApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", home.appendingPathComponent("Applications").path]
        var urls: [URL] = []
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    urls.append(item)
                } else if root == "/Applications", (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          let inner = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    urls += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        let own = Bundle.main.bundleIdentifier
        return urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != own,
                  !PlayerID.nativeBundleIDs.contains(id) else { return nil }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return InstalledApp(bundleID: id, name: name, category: bundle.infoDictionary?["LSApplicationCategoryType"] as? String, path: url.path)
        }
    }
}
