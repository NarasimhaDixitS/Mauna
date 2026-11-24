import AppKit
import SwiftUI

/// Popover rules list: app icon, name, trigger badge, and "now" while the rule is in charge.
/// The active row's tint fades in over 0.2 s (DESIGN.md › Motion).
struct RulesList: View {
    let coordinator: RuleCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Rules")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xs)
                .padding(.bottom, Spacing.xxs)

            ForEach(coordinator.rules) { rule in
                RuleRow(rule: rule, isActive: coordinator.isActive(rule))
            }
        }
    }
}

private struct RuleRow: View {
    let rule: Rule
    let isActive: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: AppIcon.image(for: rule.bundleID))
                .resizable()
                .frame(width: Size.rowAppIcon, height: Size.rowAppIcon)

            Text(rule.appName)
                .font(.body)
                .lineLimit(1)

            if isActive {
                Text("now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.accentText)
                    .transition(.opacity)
            }

            Spacer(minLength: Spacing.s)

            Text(badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
                .padding(.horizontal, Spacing.s - 2)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(.quaternary))
        }
        .padding(.horizontal, Spacing.xs)
        .frame(height: Size.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(isActive ? AnyShapeStyle(.accentTint) : AnyShapeStyle(.clear))
        )
        .animation(.maunaEaseOut(MotionDuration.rowHighlight), value: isActive)
        .accessibilityElement(children: .combine)
    }

    private var badgeText: String {
        rule.action == .ducked ? "\(rule.trigger.badge) · Lower" : rule.trigger.badge
    }
}

enum AppIcon {
    /// The app's own icon, or a generic app icon if it isn't installed.
    static func image(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let workspace = NSWorkspace.shared
        let image = workspace.urlForApplication(withBundleIdentifier: bundleID)
            .map { workspace.icon(forFile: $0.path) }
            ?? workspace.icon(for: .application)
        cache[bundleID] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]
}
