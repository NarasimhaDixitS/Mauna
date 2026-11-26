import Foundation
import Observation
import StoreKit

/// Mauna Pro through the Mac App Store: one purchase, plus a free 14-day trial taken as a $0 purchase
/// (Apple's way to offer a trial on a one-time purchase). Prices come from the App Store, in the
/// customer's own currency. While testing, Xcode answers from AppStore/Mauna.storekit.
///
/// The direct build gets its licence in Phase 6b (Lemon Squeezy). Until then it runs as Pro.
@MainActor
@Observable
final class Store {
    static let proID = "in.throttlelabs.mauna.pro"
    static let trialID = "in.throttlelabs.mauna.trial"

    private(set) var plan: Plan {
        didSet {
            guard plan != oldValue else { return }
            UserDefaults.standard.set(plan.unlocksPro, forKey: Keys.lastKnownPro)
            onPlanChange?(plan)
        }
    }
    private(set) var pro: Product?
    private(set) var trial: Product?
    /// The trial can be taken once.
    private(set) var trialTaken = false
    /// Products are still loading from the App Store.
    private(set) var isLoading = true

    /// Called whenever the plan changes, so rules and players follow at once.
    @ObservationIgnored var onPlanChange: ((Plan) -> Void)?

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    private enum Keys {
        static let lastKnownPro = "lastKnownPro"
    }

    /// Purchases happen only in the App Store build.
    static var sellsInApp: Bool {
        #if APP_STORE
        true
        #else
        false
        #endif
    }

    init() {
        #if APP_STORE
        // Start from what we knew last time, so Pro features don't blink off while the App Store answers.
        let knewPro = UserDefaults.standard.bool(forKey: Keys.lastKnownPro)
        plan = knewPro ? .pro : .free
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { [weak self] in await self?.load() }
        #else
        plan = .pro
        isLoading = false
        #endif
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        if let products = try? await Product.products(for: [Self.proID, Self.trialID]) {
            pro = products.first { $0.id == Self.proID }
            trial = products.first { $0.id == Self.trialID }
        }
        await refresh()
        isLoading = false
    }

    /// Re-reads what this Apple Account owns.
    func refresh() async {
        #if DEBUG
        if previewing { return }
        #endif
        var ownsPro = false
        var trialStart: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.proID: ownsPro = true
            case Self.trialID: trialStart = transaction.purchaseDate
            default: break
            }
        }
        trialTaken = trialStart != nil
        plan = Plan.current(ownsPro: ownsPro, trialStartedAt: trialStart, now: .now)
        scheduleExpiry()
    }

    /// When the trial ends, move to Free at that moment, even if Mauna has been running all along.
    private func scheduleExpiry() {
        expiry?.cancel()
        guard case .trial(let end) = plan else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: Buying

    enum Outcome: Equatable {
        case unlocked
        case cancelled
        /// Waiting on Ask to Buy or a bank check. Unlocks by itself when approved.
        case pending
        case failed(String)
    }

    /// Apple's own purchase sheet (Touch ID or password). Nothing else to type.
    func buy(_ product: Product) async -> Outcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The App Store couldn't confirm this purchase. Try Restore Purchase.")
                }
                await transaction.finish()
                await refresh()
                return plan.unlocksPro ? .unlocked : .failed("Something went wrong. Try Restore Purchase.")
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Restore Purchase: asks the App Store for this account's purchases (may ask to sign in).
    func restore() async -> Outcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        await refresh()
        return plan == .pro ? .unlocked : .failed("No Mauna Pro purchase was found for this Apple Account.")
    }

    // MARK: Debug

    #if DEBUG
    @ObservationIgnored private var previewing = false
    /// Design renders and debugging: pretend to be on this plan, whatever the App Store says.
    func preview(_ plan: Plan, trialTaken: Bool? = nil) {
        previewing = true
        self.plan = plan
        if let trialTaken { self.trialTaken = trialTaken }
        isLoading = false
    }

    /// Back to what the App Store (or Xcode's StoreKit test file) says.
    func endPreview() async {
        previewing = false
        await refresh()
    }
    #endif
}
