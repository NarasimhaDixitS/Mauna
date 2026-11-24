import AppKit
import SwiftUI

/// Popover rules: `.sl` section label with the waiting ring, the quick rule for the app in front,
/// then `.row`s (34pt, 10pt padding, hover fill, accent tint while in charge, "now" slides in 3pt).
struct RulesList: View {
    let model: AppModel
    private var coordinator: RuleCoordinator { model.rules }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Rules")
                Spacer()
                if coordinator.isWaiting {
                    HStack(spacing: 6) {
                        PendingRing()
                        Text("Waiting \(AudioTiming.debounce.formatted()) s")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .transition(.opacity)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.15), value: coordinator.isWaiting)

            Group {
                if let app = model.quickRuleCandidate {
                    QuickRuleRow(app: app, coordinator: coordinator)
                }

                ForEach(coordinator.allRules) { rule in
                    RuleRow(rule: rule, isActive: coordinator.isActive(rule), isQuick: coordinator.isQuick(rule)) {
                        coordinator.keep(rule)
                    }
                }

                if coordinator.allRules.isEmpty && model.quickRuleCandidate == nil {
                    EmptyRules()
                }
            }
            .opacity(coordinator.isEnabled ? 1 : 0.5)
        }
    }
}

/// The app in front has no rule: quiet it until it quits, in one click. Acts at once, no 1.5 s wait.
private struct QuickRuleRow: View {
    let app: AppModel.FrontApp
    let coordinator: RuleCoordinator

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: app.bundleID)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .lineLimit(1)
                Text("Quiet until it quits")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 0) {
                Button("Pause") { coordinator.addQuickRule(bundleID: app.bundleID, appName: app.name, action: .paused) }
                Button("Lower") { coordinator.addQuickRule(bundleID: app.bundleID, appName: app.name, action: .ducked) }
            }
            .buttonStyle(.maunaGhost)
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .rowHover()
    }
}

private struct RuleRow: View {
    let rule: Rule
    let isActive: Bool
    let isQuick: Bool
    let keep: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: rule.bundleID)

            HStack(spacing: 6) {
                Text(rule.appName)
                    .lineLimit(1)
                Text("now")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.accentText)
                    .opacity(isActive ? 1 : 0)
                    .offset(x: isActive ? 0 : -3)
                    .animation(.maunaEaseOut(MotionDuration.rowHighlight), value: isActive)
                    .accessibilityHidden(!isActive)
            }

            Spacer(minLength: 6)

            if isQuick {
                Button("Keep", action: keep)
                    .buttonStyle(.maunaGhost)
                    .help("Make it a rule")
            }

            Badge(symbol: isQuick ? "hourglass" : rule.trigger.symbol, text: badgeText, isAccent: isActive)
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .rowHover(isActive: isActive)
        .accessibilityElement(children: .combine)
    }

    private var badgeText: String {
        let base = isQuick ? "Until quit" : rule.trigger.badge
        return rule.action == .ducked ? "\(base) · Lower" : base
    }
}

/// No rules yet: one plain sentence, then the next step.
private struct EmptyRules: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No quiet apps yet")
                .font(.headline)
            Text("Add an app, and Mauna will step your music aside when you use it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsButton(title: "Add App…", symbol: "plus", tab: .rules)
                .buttonStyle(.maunaSecondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// A small copy for menus, which draw images at their own size.
    static func menuImage(for bundleID: String) -> NSImage {
        let source = image(for: bundleID)
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }

    private static var cache: [String: NSImage] = [:]
}
