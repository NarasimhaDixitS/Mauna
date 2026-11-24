import AppKit

/// Watches which app is in front and which apps are running (NSWorkspace notifications),
/// and whether anyone is at the Mac (screen saver, lock, sleep).
///
/// Mauna itself, the screen saver and the lock screen are never "the app in front":
/// opening the popover or walking away doesn't end an "In front" rule.
final class AppWatcher {
    var onChange: ((AppSnapshot) -> Void)?
    var onAwayChange: ((Bool) -> Void)?
    private(set) var snapshot = AppSnapshot()
    var isAway: Bool { !awayReasons.isEmpty }

    private enum AwayReason { case screenSaver, locked, displaysAsleep, macAsleep, otherUser }

    private var awayReasons: Set<AwayReason> = []
    private var observers: [NSObjectProtocol] = []
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        snapshot = read(previousFrontmost: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let activatedID = name == NSWorkspace.didActivateApplicationNotification ? app?.bundleIdentifier : nil
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // A real app came to the front: someone is using the Mac. Safety net in case a
                    // "back" notification never arrived.
                    if let activatedID, !self.isIgnored(activatedID) { self.setAll(away: false) }
                    self.changed()
                }
            })
        }
        observeAway()
    }

    // MARK: App changes

    private func changed() {
        let next = read(previousFrontmost: snapshot.frontmost)
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }

    private func read(previousFrontmost: String?) -> AppSnapshot {
        let workspace = NSWorkspace.shared
        var front = workspace.frontmostApplication?.bundleIdentifier
        if let id = front, isIgnored(id) { front = previousFrontmost }
        let running = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
        return AppSnapshot(frontmost: front, running: running)
    }

    /// Apps that can be in front without meaning "the user switched apps".
    private func isIgnored(_ bundleID: String) -> Bool {
        bundleID == ownBundleID
            || bundleID == "com.apple.loginwindow"
            || bundleID.hasPrefix("com.apple.ScreenSaver")
    }

    // MARK: Away

    private func observeAway() {
        let distributed = DistributedNotificationCenter.default()
        let distributedPairs: [(String, AwayReason, Bool)] = [
            ("com.apple.screensaver.didstart", .screenSaver, true),
            ("com.apple.screensaver.didstop", .screenSaver, false),
            ("com.apple.screenIsLocked", .locked, true),
            ("com.apple.screenIsUnlocked", .locked, false),
        ]
        for (name, reason, away) in distributedPairs {
            observers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(reason, away: away) }
            })
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let workspacePairs: [(Notification.Name, AwayReason, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, .displaysAsleep, true),
            (NSWorkspace.screensDidWakeNotification, .displaysAsleep, false),
            (NSWorkspace.willSleepNotification, .macAsleep, true),
            (NSWorkspace.didWakeNotification, .macAsleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .otherUser, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .otherUser, false),
        ]
        for (name, reason, away) in workspacePairs {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(reason, away: away) }
            })
        }
    }

    private func set(_ reason: AwayReason, away: Bool) {
        let wasAway = isAway
        if away { awayReasons.insert(reason) } else { awayReasons.remove(reason) }
        if isAway != wasAway { onAwayChange?(isAway) }
    }

    private func setAll(away: Bool) {
        guard !away, isAway else { return }
        awayReasons.removeAll()
        onAwayChange?(false)
    }
}
