import StoreKit
import Foundation
import Combine

@MainActor
final class MembershipStore: ObservableObject {

    static let productIDs = [
        "danglingmind.motorcade.membership.yearly",
        "danglingmind.motorcade.membership.monthly",
    ]

    @Published var products: [Product] = []
    @Published var isPremium: Bool = false
    @Published var premiumEndsAt: Date? = nil
    @Published var purchaseError: String? = nil
    @Published var isLoading: Bool = false
    @Published var productsLoadFailed: Bool = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        guard products.isEmpty else { return }
        productsLoadFailed = false
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            if fetched.isEmpty {
                productsLoadFailed = true
            } else {
                products = fetched.sorted { $0.price > $1.price }
            }
        } catch {
            productsLoadFailed = true
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
            purchaseError = "Restore failed. Try again."
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

    var yearlyProduct: Product? { products.first { $0.id.contains("yearly") } }
    var monthlyProduct: Product? { products.first { $0.id.contains("monthly") } }

    func savingsPercent(monthly: Product, yearly: Product) -> Int {
        let monthlyAnnual = monthly.price * 12
        guard monthlyAnnual > 0 else { return 0 }
        let fraction = (monthlyAnnual - yearly.price) / monthlyAnnual
        return NSDecimalNumber(decimal: fraction * 100).intValue
    }
}
