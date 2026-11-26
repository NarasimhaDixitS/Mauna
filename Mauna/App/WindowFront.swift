import AppKit

/// Brings Mauna's windows all the way to the front.
///
/// Mauna lives in the menu bar with no Dock icon. Since macOS 14, apps like that ask to come forward
/// and macOS often declines, so a window you just asked for opens behind the app you were using.
/// When *you* open one of Mauna's windows (Pro, Settings, the welcome window), Mauna takes the front
/// for real. Only ever in answer to your click, never by itself.
@MainActor
enum WindowFront {
    /// Make Mauna the active app, even though another app was in front.
    static func activate() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        // The cooperative call above can be declined; this one isn't, and it's what the user asked for.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Show `window` in front of everything and give it the keyboard.
    static func show(_ window: NSWindow) {
        activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// SwiftUI's Settings window, after `openSettings()`. It appears a moment later, so raise it then too.
    static func raiseSettings() {
        activate()
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApplication.shared.windows where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                    show(window)
                }
            }
        }
    }
}
