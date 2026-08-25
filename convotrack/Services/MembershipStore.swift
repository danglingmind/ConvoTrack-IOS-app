import StoreKit
import Foundation
import Combine

@MainActor
final class MembershipStore: ObservableObject {

    static let productIDs = [
        "danglingmind.convotrack.membership.yearly",
        "danglingmind.convotrack.membership.monthly",
    ]

    @Published private(set) var products: [Product] = []
    @Published var isPremium: Bool = false
    @Published var premiumEndsAt: Date? = nil
    @Published var purchaseError: String? = nil
    @Published var isLoading: Bool = false
    @Published private(set) var productsLoadFailed: Bool = false

    /// Subscription groups this account may still receive an introductory offer in.
    /// Eligibility is per group, not per product, so one entry covers both plans.
    @Published private(set) var introEligibleGroupIDs: Set<String> = []

    private var transactionListener: Task<Void, Never>?
    private var storefrontListener: Task<Void, Never>?

    /// Storefront the current `products` were priced in. Prices are per-country, so
    /// a cached product from another storefront is a wrong price, not a stale one.
    private var loadedStorefrontID: String?
    private var loadTask: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        storefrontListener  = listenForStorefrontChanges()
    }

    deinit {
        transactionListener?.cancel()
        storefrontListener?.cancel()
    }

    // MARK: - Load Products

    /// - Parameter force: refetch even when products are already cached. Used by the
    ///   Retry button and by storefront changes.
    func loadProducts(force: Bool = false) async {
        if !force, !products.isEmpty, loadedStorefrontID != nil { return }

        // Two concurrent `.task` calls must not fire two StoreKit requests.
        if let inFlight = loadTask {
            await inFlight.value
            return
        }
        let task = Task<Void, Never> { [weak self] in
            await self?.performLoad(force: force)
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad(force: Bool) async {
        productsLoadFailed = false
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            if fetched.isEmpty {
                products = []
                productsLoadFailed = true
                loadedStorefrontID = nil
            } else {
                // Longest billing period first; price descending only as a tiebreak.
                products = fetched.sorted { lhs, rhs in
                    let l = PlanPeriod(lhs)?.months ?? 0
                    let r = PlanPeriod(rhs)?.months ?? 0
                    return l == r ? lhs.price > rhs.price : l > r
                }
                loadedStorefrontID = await Storefront.current?.id
                await refreshIntroEligibility()
            }
        } catch {
            // On a forced refresh we must not keep prices from the previous storefront —
            // showing a price we would not charge is worse than showing an error.
            if force {
                products = []
                loadedStorefrontID = nil
            }
            productsLoadFailed = true
        }
    }

    // MARK: - Storefront

    private func listenForStorefrontChanges() -> Task<Void, Never> {
        Task { [weak self] in
            for await storefront in Storefront.updates {
                guard let self else { return }
                await self.handleStorefrontChange(storefront)
            }
        }
    }

    private func handleStorefrontChange(_ storefront: Storefront) async {
        guard storefront.id != loadedStorefrontID else { return }
        products = []
        loadedStorefrontID = nil
        await loadProducts(force: true)
        await refreshEntitlements()
    }

    /// Self-heals a storefront change that arrived while the app was suspended, where
    /// `Storefront.updates` is not guaranteed to deliver. Cheap enough to call on every
    /// paywall presentation.
    func refreshIfStorefrontChanged() async {
        let current = await Storefront.current?.id
        if current != loadedStorefrontID {
            await loadProducts(force: true)
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        isLoading = true
        defer { isLoading = false }
        purchaseError = nil

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // JWS must be read from VerificationResult before unwrapping
            let jws = verification.jwsRepresentation
            let transaction = try checkVerified(verification)
            let confirmed = await activateOnServer(jws: jws)
            if confirmed { await transaction.finish() }
            await refreshEntitlements()
            await refreshIntroEligibility()

        case .userCancelled:
            break

        case .pending:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = UserFacingError.restoreFailed
        }
    }

    // MARK: - Entitlement Check

    func refreshEntitlements() async {
        var foundPremium = false
        var latestExpiry: Date? = nil

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }

            if let expDate = transaction.expirationDate, expDate > Date() {
                foundPremium = true
                if latestExpiry == nil || expDate > latestExpiry! {
                    latestExpiry = expDate
                }
            }
        }

        isPremium = foundPremium
        premiumEndsAt = latestExpiry
    }

    // MARK: - Introductory Offers

    /// Defensive only: no introductory offer is configured today (the trial is the
    /// in-app free-ride allowance). This exists so that if one is ever added in App
    /// Store Connect the paywall discloses it correctly instead of showing bare price.
    private func refreshIntroEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            guard let sub = product.subscription else { continue }
            let groupID = sub.subscriptionGroupID
            guard !eligible.contains(groupID) else { continue }
            if await sub.isEligibleForIntroOffer {
                eligible.insert(groupID)
            }
        }
        introEligibleGroupIDs = eligible
    }

    func introductoryOffer(for product: Product) -> Product.SubscriptionOffer? {
        guard let sub = product.subscription,
              let offer = sub.introductoryOffer,
              introEligibleGroupIDs.contains(sub.subscriptionGroupID) else { return nil }
        return offer
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                let jws = result.jwsRepresentation
                guard let transaction = try? self.checkVerified(result) else { continue }
                let confirmed = await self.activateOnServer(jws: jws)
                if confirmed { await transaction.finish() }
                await self.refreshEntitlements()
            }
        }
    }

    // MARK: - Server Sync

    // Returns true when server confirms — callers finish() the transaction only on true.
    @discardableResult
    private func activateOnServer(jws: String) async -> Bool {
        do {
            _ = try await APIClient.shared.activateMembership(signedTransaction: jws)
            return true
        } catch {
            // Non-fatal: local StoreKit entitlement is still valid.
            // finish() is deferred — server will retry via Transaction.updates on next launch.
            return false
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }

    /// Shortest plan on offer — the yardstick every other plan's saving is measured against.
    var baselinePlan: Product? {
        products.min { lhs, rhs in
            (PlanPeriod(lhs)?.months ?? .greatestFiniteMagnitude)
                < (PlanPeriod(rhs)?.months ?? .greatestFiniteMagnitude)
        }
    }

    /// Plan with the largest per-month saving versus the baseline; carries the SAVE badge.
    var bestValuePlan: Product? {
        guard let baseline = baselinePlan else { return nil }
        return products
            .filter { $0.id != baseline.id }
            .compactMap { p -> (Product, Int)? in
                guard let pct = savingsPercent(of: p, versus: baseline) else { return nil }
                return (p, pct)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Whole-percent saving of `candidate` against `baseline`, compared on a per-month
    /// basis so plans of different lengths are comparable. Returns nil when there is no
    /// genuine saving. Rounds half-up rather than truncating.
    func savingsPercent(of candidate: Product, versus baseline: Product) -> Int? {
        guard let c = PlanPeriod(candidate)?.monthlyEquivalent(of: candidate.price),
              let b = PlanPeriod(baseline)?.monthlyEquivalent(of: baseline.price),
              b > 0 else { return nil }

        var raw = (b - c) / b * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        let pct = NSDecimalNumber(decimal: rounded).intValue
        return (1...99).contains(pct) ? pct : nil
    }
}
