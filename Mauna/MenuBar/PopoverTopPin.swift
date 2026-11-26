import AppKit
import SwiftUI

/// Keeps the popover hanging from the menu bar when its content grows or shrinks.
///
/// macOS places the popover under the menu bar icon when it opens. In a full-screen Space the menu
/// bar hides again after a moment, taking the icon with it. When the content then changes height
/// (unfolding the rules or the player list), SwiftUI re-anchors the popover to that hidden icon,
/// above the top of the screen, and the popover's top is cut off.
///
/// So on every resize or move, in the same moment, this puts the top back where it was when the
/// popover opened, and never higher than the bottom of the menu bar.
struct PopoverTopPin: NSViewRepresentable {
    func makeNSView(context: Context) -> PinView { PinView() }
    func updateNSView(_ view: PinView, context: Context) {}

    final class PinView: NSView {
        /// The popover's top edge, in screen coordinates, as macOS placed it when it opened.
        private var top: CGFloat?
        private var observers: [NSObjectProtocol] = []
        private var pinning = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            top = nil
            guard let window else { return }
            remember()

            let center = NotificationCenter.default
            let watch: (NSNotification.Name, @escaping @MainActor (PinView) -> Void) -> Void = { name, action in
                self.observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self { action(self) } }
                })
            }
            // Each time it opens, macOS places it afresh under the icon: remember that top.
            watch(NSWindow.didBecomeKeyNotification) { $0.remember() }
            watch(NSWindow.didChangeOcclusionStateNotification) { view in
                if view.window?.occlusionState.contains(.visible) == true { view.remember() }
            }
            // After SwiftUI resizes or re-anchors it, put the top back at once, inside the same
            // notification: the corrected frame is what reaches the screen, so nothing jumps.
            // (Correcting a run loop later showed the wrong position for one frame.)
            watch(NSWindow.didResizeNotification) { $0.pin() }
            watch(NSWindow.didMoveNotification) { $0.pin() }
        }

        /// The highest the popover's top may sit: just under the menu bar.
        private var ceiling: CGFloat? {
            guard let screen = window?.screen ?? NSScreen.main else { return nil }
            var menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            if menuBar < 1 {
                // Full screen: the menu bar is hidden, so visibleFrame doesn't show it. Use its height.
                menuBar = max(NSApplication.shared.mainMenu?.menuBarHeight ?? 0, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            }
            return screen.frame.maxY - menuBar
        }

        private func remember() {
            guard let window else { return }
            top = min(window.frame.maxY, ceiling ?? .infinity)
        }

        private func pin() {
            guard !pinning, let window else { return }
            let target = min(top ?? window.frame.maxY, ceiling ?? .infinity)
            var frame = window.frame
            guard abs(frame.maxY - target) > 0.5 else { return }
            frame.origin.y = target - frame.height
            // Never below the bottom of the screen either.
            if let screen = window.screen {
                frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY)
            }
            pinning = true
            window.setFrameOrigin(frame.origin)
            pinning = false
        }
    }
}
