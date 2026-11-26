import AppKit
import SwiftUI

/// Popover rules, in the order that matters now: rules acting, quick rules, apps that are open, then the rest.
/// Four show; the others fold into one "Also watching" row of their icons, which unfolds the full list in
/// place (the same gesture as the player card). It always opens folded. A hidden rule that starts acting
/// moves up into view by itself, so you never have to unfold to see why the music changed.
struct RulesList: View {
    let model: AppModel
    #if DEBUG
    /// MAUNA_SNAPSHOT_RULES_OPEN=1 renders the list unfolded.
    @State private var showAll = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_RULES_OPEN"] != nil
    #else
    @State private var showAll = false
    #endif
    private var coordinator: RuleCoordinator { model.rules }

    /// Rules shown before the fold.
    static let visibleCount = 4
    /// Unfolded, the list scrolls beyond this many rows, so the popover never grows past the screen.
    static let maxRows = 10

    var body: some View {
        let ordered = self.ordered
        let folds = ordered.count > Self.visibleCount + 1   // never fold away just one rule
        let shown = folds && !showAll ? Array(ordered.prefix(Self.visibleCount)) : ordered
        let hidden = folds && !showAll ? Array(ordered.dropFirst(Self.visibleCount)) : []

        VStack(alignment: .leading, spacing: 0) {
            // A suggestion, not a rule: its own card above the list.
            if let app = model.quickRuleCandidate {
                QuickRuleCard(app: app, coordinator: coordinator)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            header(count: ordered.count)

            Group {
                rows(shown, scrolls: showAll && shown.count > Self.maxRows)

                if folds {
                    FoldRow(hidden: hidden, isOpen: showAll) {
                        withAnimation(.maunaSpring) { showAll.toggle() }
                    }
                }

                if coordinator.allRules.isEmpty && model.quickRuleCandidate == nil {
                    EmptyRules()
                }
            }
            .opacity(coordinator.isEnabled ? 1 : 0.5)
        }
        .animation(.maunaSpring, value: ordered.map(\.id))
        .animation(.maunaEaseOut(0.2), value: model.quickRuleCandidate)
    }

    /// "Rules  9", and the waiting ring while a change waits out the debounce.
    private func header(count: Int) -> some View {
        HStack(spacing: 6) {
            Text("Rules")
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
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
    }

    @ViewBuilder
    private func rows(_ rules: [Rule], scrolls: Bool) -> some View {
        let list = VStack(spacing: 0) {
            ForEach(rules) { rule in
                RuleRow(rule: rule, isActive: coordinator.isActive(rule), isQuick: coordinator.isQuick(rule)) {
                    coordinator.keep(rule)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Design renders can't draw scroll views, so they get the flat list.
        if scrolls && ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT"] == nil {
            ScrollView { list }
                .frame(height: CGFloat(Self.maxRows) * 38)
                .scrollIndicators(.automatic)
        } else {
            list
        }
    }

    /// Acting first, then quick rules, then apps that are open, then the rest. Your order within each.
    private var ordered: [Rule] {
        func rank(_ rule: Rule) -> Int {
            if coordinator.isActive(rule) { return 0 }
            if coordinator.isQuick(rule) { return 1 }
            if coordinator.running.contains(rule.bundleID) { return 2 }
            return 3
        }
        return coordinator.allRules.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}

/// The fold: overlapping icons of the rules not shown, "Also watching", and how many.
/// Open, it becomes "Show fewer".
private struct FoldRow: View {
    let hidden: [Rule]
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                if isOpen {
                    Text("Show fewer")
                        .foregroundStyle(.secondary)
                } else {
                    IconStack(bundleIDs: hidden.map(\.bundleID))
                    Text("Also watching")
                        .foregroundStyle(.secondary)
                    Text("\(hidden.count) more")
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.body)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .contentShape(Rectangle())
            .rowHover()
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(isOpen ? "Show fewer rules" : "Also watching \(hidden.count) more apps")
    }
}

/// Up to four app icons overlapping like a stack of cards, the first on top.
private struct IconStack: View {
    let bundleIDs: [String]
    private let size: CGFloat = 20
    private let step: CGFloat = 15

    var body: some View {
        let ids = Array(bundleIDs.prefix(4))
        ZStack(alignment: .leading) {
            ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                AppIconView(bundleID: id, size: size)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, x: 1, y: 0)
                    .offset(x: CGFloat(index) * step)
                    .zIndex(Double(ids.count - index))
            }
        }
        .frame(width: size + CGFloat(max(ids.count - 1, 0)) * step, alignment: .leading)
    }
}

/// The app in front has no rule: a soft card above the list offers to quiet music until it quits,
/// in one click. Acts at once, no 1.5 s wait. Gone the moment you pick, or when you switch apps.
private struct QuickRuleCard: View {
    let app: AppModel.FrontApp
    let coordinator: RuleCoordinator

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            AppIconView(bundleID: app.bundleID, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("In front · no rule yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Button("Pause") { coordinator.addQuickRule(bundleID: app.bundleID, appName: app.name, action: .paused) }
                    .help("Pause music until \(app.name) quits")
                Button("Lower") { coordinator.addQuickRule(bundleID: app.bundleID, appName: app.name, action: .ducked) }
                    .help("Lower music until \(app.name) quits")
            }
            .buttonStyle(.maunaSmall)
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(shape.fill(.popRow))
        .overlay {
            shape.strokeBorder(.primary.opacity(0.05), lineWidth: 0.5)
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)),
                lineWidth: 0.5
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(app.name) is in front and has no rule")
    }
}

/// A rule: icon, name, "now" while it acts. At rest the badge is just its symbol; the words
/// ("Front · Lower") appear under the pointer and while the rule acts, so nine rows never shout at once.
private struct RuleRow: View {
    let rule: Rule
    let isActive: Bool
    let isQuick: Bool
    let keep: () -> Void
    @State private var hovering = false

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

            Badge(symbol: isQuick ? "hourglass" : rule.trigger.symbol, text: badgeText, isAccent: isActive,
                  restSymbol: rule.action == .ducked ? "speaker.wave.1.fill" : nil,
                  showsText: isActive || hovering || isQuick)
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .rowHover(isActive: isActive)
        .onHover { hovering = $0 }
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
