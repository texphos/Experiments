import Foundation
import Observation
import StoreKit

/// One non-consumable, verified locally by StoreKit 2. No server, no account.
///
/// Pro is only ever unlocked from a *verified* entry in `Transaction.currentEntitlements`. Purchase results,
/// messages and the cached flag in `AppState` never unlock anything on their own. Debug builds use the local
/// `Hearthday.storekit` configuration; release builds talk to the App Store, where nothing is configured until
/// the owner creates the product in App Store Connect.
@MainActor
@Observable
final class ProStore {
    static let defaultProductID = "app.hearthday.pro"

    enum LoadState: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    let productID: String
    private(set) var product: Product?
    private(set) var loadState: LoadState = .loading
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isPro = false
    var purchaseMessage: String?

    @ObservationIgnored var onEntitlementChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(productID: String = ProStore.defaultProductID) {
        self.productID = productID
    }

    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                    }
                    await self?.refreshEntitlement()
                }
            }
        }
        await refreshEntitlement()
        await loadProduct()
    }

    func loadProduct() async {
        loadState = .loading
        do {
            product = try await Product.products(for: [productID]).first
            loadState = product == nil
                ? .unavailable("Hearthday Pro isn’t available from the App Store right now. Everything free keeps working.")
                : .ready
        } catch {
            loadState = .unavailable("Couldn’t reach the App Store. Check your connection and try again.")
        }
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        purchaseMessage = nil
        do {
            let result = try await product.purchase()
            await refreshEntitlement()
            purchaseMessage = Self.message(for: result, entitled: isPro)
        } catch {
            await refreshEntitlement()
            purchaseMessage = isPro ? Self.unlockedMessage : Self.errorMessage
        }
    }

    // An error or an unverified result doesn't tell the app whether the App Store charged the baker, so these
    // messages never say either way. They point to Restore and to Apple's purchase history and support instead.
    static let unlockedMessage = "Thank you. Pro is unlocked on this Apple Account."
    static let errorMessage = "The App Store reported a problem, so Pro isn’t active on this iPhone yet. Tap Restore purchase in a moment. If the purchase appears in your Apple Account purchase history and Pro still isn’t active, use Report a Problem there or contact Apple Support."
    static let unverifiedMessage = "The App Store couldn’t verify this purchase, so Pro isn’t active yet. Tap Restore purchase in a moment. If the purchase appears in your Apple Account purchase history and Pro still isn’t active, use Report a Problem there or contact Apple Support."
    static let notActiveYetMessage = "The App Store accepted the purchase but Pro isn’t active on this iPhone yet. Tap Restore purchase in a moment."
    static let pendingMessage = "Your purchase is waiting for approval. Pro unlocks as soon as it goes through."

    /// What to tell the baker after a purchase attempt. Success is only claimed when the entitlement is verified.
    static func message(for result: Product.PurchaseResult, entitled: Bool) -> String? {
        switch result {
        case .success(.verified):
            return entitled ? unlockedMessage : notActiveYetMessage
        case .success(.unverified):
            return entitled ? unlockedMessage : unverifiedMessage
        case .pending:
            return pendingMessage
        case .userCancelled:
            return nil
        @unknown default:
            return entitled ? nil : errorMessage
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseMessage = isPro ? "Pro restored." : "No previous Pro purchase was found for this Apple Account."
        } catch StoreKitError.userCancelled {
            purchaseMessage = nil
        } catch {
            purchaseMessage = "Couldn’t reach the App Store to restore. Try again when you’re online."
        }
    }

    func refreshEntitlement() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == productID, t.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
        onEntitlementChange?(owned)
    }
}
