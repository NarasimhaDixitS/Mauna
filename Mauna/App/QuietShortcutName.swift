import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌃⌥Space by default. The user can record their own in Settings.
    static let quietMusic = Self("quietMusic", initial: .init(.space, modifiers: [.control, .option]))
}

extension QuietShortcut.Mode {
    /// UserDefaults key for what the shortcut does: pause or lower.
    static let storageKey = "shortcutMode"

    static var saved: Self {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .pause
    }
}
