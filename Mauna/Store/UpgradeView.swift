import AppKit
import StoreKit
import SwiftUI

/// Mauna Pro: what it unlocks, the price from the App Store, and Apple's own purchase sheet
/// (Touch ID). No forms, no keys. After buying (or starting the trial) the window turns into a short
/// "Welcome to Pro" moment: the tile lights up and the wave rises from ❙❙ to full.
struct UpgradeView: View {
    static let size = CGSize(width: 440, height: 640)

    let model: AppModel
    /// What you tried to use, so the pitch starts there.
    let feature: ProFeature?
    /// Just finished the welcome window: lead with the free trial.
    var afterOnboarding = false
    let close: () -> Void

    private enum Stage: Equatable { case pitch, welcome(trial: Bool) }

    @State private var stage: Stage
    @State private var busy: Busy?
    @State private var message: String?
    /// Resting rules when the window opened, for "Your 5 resting rules are back on."
    @State private var restingBefore = 0

    private enum Busy { case buying, trial, restoring }

    init(model: AppModel, feature: ProFeature?, afterOnboarding: Bool = false, close: @escaping () -> Void) {
        self.model = model
        self.feature = feature
        self.afterOnboarding = afterOnboarding
        self.close = close
        #if DEBUG
        let welcome = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_WELCOME"] != nil
        _stage = State(initialValue: welcome ? .welcome(trial: false) : .pitch)
        #else
        _stage = State(initialValue: .pitch)
        #endif
    }

    private var store: Store { model.store }

    var body: some View {
        ZStack {
            // A soft indigo light from the top, behind the tile.
            RadialGradient(colors: [Color(hex: 0x6F6AF0).opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0), startRadius: 0, endRadius: 360)
                .ignoresSafeArea()

            switch stage {
            case .pitch:
                pitch.transition(.opacity)
            case .welcome(let trial):
                WelcomeToPro(trial: trial, restingBefore: restingBefore, endsAt: trialEnd, close: close)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.maunaEaseOut(0.35), value: stage)
        .onAppear { restingBefore = model.rules.restingIDs.count }
    }

    // MARK: Pitch

    private var pitch: some View {
        VStack(spacing: 0) {
            StatusTile(state: .playing, isActing: true, size: 64)
                .padding(.top, 44)

            Text("Mauna Pro")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 18)
            Text(headline)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 48)

            VStack(spacing: 2) {
                ForEach(ProFeature.allCases) { item in
                    FeatureRow(feature: item, isHighlighted: item == feature)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            actions
                .padding(.horizontal, 40)
                .padding(.bottom, 22)
        }
    }

    private var headline: String {
        if afterOnboarding {
            return "Your quiet apps are ready. Free runs two of them; try everything free for 14 days."
        }
        return switch feature {
        case .moreRules: "Free keeps two rules. Pro quiets music for every app you use."
        case .everyTrigger: "Quiet music while an app is open, not only when it's in front."
        case .lower: "Keep your music playing softly instead of pausing it."
        case .youTubeMusic: "Bring YouTube Music in Chrome and Safari along."
        case .customFade: "Choose how gently your music fades away and back."
        case nil: "Everything Mauna can do. One purchase, yours for good."
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if store.isLoading && store.pro == nil {
                Button {} label: {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
                .buttonStyle(.maunaPrimary)
                .disabled(true)
            } else if let price = store.pro?.displayPrice ?? Self.samplePrice {
                let offersTrial = (store.trial != nil || Self.samplePrice != nil) && !store.trialTaken
                if afterOnboarding && offersTrial {
                    trialButton(primary: true)
                    buyButton(price, primary: false)
                } else {
                    buyButton(price, primary: true)
                    if offersTrial { trialButton(primary: false) }
                }

                Text(fineprint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("The App Store isn't answering right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await store.load() } }
                    .buttonStyle(.maunaSecondary)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            HStack(spacing: 16) {
                Button(busy == .restoring ? "Restoring…" : "Restore Purchase") { Task { await restore() } }
                    .disabled(busy != nil)
                Text("·").foregroundStyle(.quaternary)
                Button("Not Now", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(PlainTextButtonStyle())
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .animation(.maunaEaseOut(0.2), value: message)
    }

    /// Design renders only: the App Store isn't reachable from a render, so show this price.
    private static var samplePrice: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_PRICE"]
        #else
        nil
        #endif
    }

    @ViewBuilder private func buyButton(_ price: String, primary: Bool) -> some View {
        let button = Button { if let pro = store.pro { Task { await buy(pro, trial: false) } } } label: {
            HStack(spacing: 8) {
                if busy == .buying { ProgressView().controlSize(.small).tint(primary ? .white : nil) }
                Text("Unlock Pro · \(price)")
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(busy != nil)
        if primary {
            button.buttonStyle(.maunaPrimary).keyboardShortcut(.defaultAction)
        } else {
            button.buttonStyle(.maunaSecondary)
        }
    }

    @ViewBuilder private func trialButton(primary: Bool) -> some View {
        let button = Button { if let trial = store.trial { Task { await buy(trial, trial: true) } } } label: {
            HStack(spacing: 8) {
                if busy == .trial { ProgressView().controlSize(.small).tint(primary ? .white : nil) }
                Text("Try Pro free for 14 days")
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(busy != nil)
        if primary {
            button.buttonStyle(.maunaPrimary).keyboardShortcut(.defaultAction)
        } else {
            button.buttonStyle(.maunaSecondary)
        }
    }

    private var fineprint: String {
        if let days = store.plan.trialDaysLeft(now: .now) {
            return "You're on the free trial: \(days) \(days == 1 ? "day" : "days") left. One purchase, no subscription."
        }
        return "One purchase, no subscription. Shared with your family through Family Sharing."
    }

    private var trialEnd: Date? {
        if case .trial(let end) = store.plan { return end }
        return nil
    }

    // MARK: Actions

    private func buy(_ product: Product, trial: Bool) async {
        busy = trial ? .trial : .buying
        message = nil
        let outcome = await store.buy(product)
        busy = nil
        switch outcome {
        case .unlocked: stage = .welcome(trial: trial)
        case .cancelled: break
        case .pending: message = "Waiting for approval. Pro unlocks by itself as soon as it's approved."
        case .failed(let text): message = text
        }
    }

    private func restore() async {
        busy = .restoring
        message = nil
        let outcome = await store.restore()
        busy = nil
        switch outcome {
        case .unlocked: stage = .welcome(trial: false)
        case .cancelled, .pending: break
        case .failed(let text): message = text
        }
    }
}

/// One thing Pro unlocks: a tinted symbol tile, a title, one plain line. The feature you reached for glows.
private struct FeatureRow: View {
    let feature: ProFeature
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.accentText)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.accentTint))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient.accentRowTint)
                .opacity(isHighlighted ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch feature {
        case .moreRules: "infinity"
        case .everyTrigger: "play.circle"
        case .lower: "speaker.wave.1.fill"
        case .youTubeMusic: "play.rectangle.fill"
        case .customFade: "waveform.path"
        }
    }

    private var title: String {
        switch feature {
        case .moreRules: "Unlimited rules"
        case .everyTrigger: "Every trigger"
        case .lower: "Lower instead of pause"
        case .youTubeMusic: "YouTube Music"
        case .customFade: "Your own fade"
        }
    }

    private var detail: String {
        switch feature {
        case .moreRules: "Every app you use, not just two."
        case .everyTrigger: "While an app is open, not only in front."
        case .lower: "Music keeps playing, softly."
        case .youTubeMusic: "In Chrome and Safari."
        case .customFade: "From instant to five slow seconds."
        }
    }
}

/// The moment after buying: the tile lights and the wave rises from ❙❙ to full, once. Nothing loops.
private struct WelcomeToPro: View {
    let trial: Bool
    let restingBefore: Int
    let endsAt: Date?
    let close: () -> Void

    @State private var lit = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            StatusTile(state: lit ? .playing : .paused, isActing: lit, size: 88)
                .scaleEffect(lit ? 1 : 0.86)
            Text(trial ? "Your Pro trial has begun" : "Welcome to Pro")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 26)
                .opacity(lit ? 1 : 0)
                .offset(y: lit ? 0 : 6)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 56)
                .opacity(lit ? 1 : 0)
                .offset(y: lit ? 0 : 6)
            Spacer()
            Button(action: close) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.maunaPrimary)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
            .opacity(lit ? 1 : 0)
        }
        .onAppear {
            withAnimation(.maunaSpring.delay(0.15)) { lit = true }
        }
    }

    private var detail: String {
        var lines: [String] = []
        if trial, let endsAt {
            lines.append("Everything is unlocked until \(endsAt.formatted(.dateTime.day().month(.wide))).")
        } else {
            lines.append("Everything Mauna can do is yours.")
        }
        if restingBefore > 0 {
            lines.append(restingBefore == 1 ? "Your resting rule is back on." : "Your \(restingBefore) resting rules are back on.")
        }
        return lines.joined(separator: " ")
    }
}

/// The upgrade window. Plain AppKit like the welcome window, so it opens only when asked.
@MainActor
enum UpgradeWindow {
    private static var window: NSWindow?

    static func show(model: AppModel, feature: ProFeature?, afterOnboarding: Bool = false) {
        window?.close()
        let view = UpgradeView(model: model, feature: feature, afterOnboarding: afterOnboarding) { close() }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: UpgradeView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "Mauna Pro"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
        WindowFront.show(window)
    }

    static func close() {
        window?.close()
        window = nil
    }
}
