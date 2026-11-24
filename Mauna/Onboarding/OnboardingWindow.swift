import AppKit
import SwiftUI

/// The welcome window. Plain AppKit, so it opens only when asked: on first launch, or from Settings › Debug.
@MainActor
enum OnboardingWindow {
    static let doneKey = "hasOnboarded"
    private static var window: NSWindow?

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    static func showIfNeeded(model: AppModel) {
        guard !isDone else { return }
        show(model: model)
    }

    static func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }
        let view = OnboardingView(model: model) {
            UserDefaults.standard.set(true, forKey: doneKey)
            close()
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    static func close() {
        window?.close()
        window = nil
    }
}
