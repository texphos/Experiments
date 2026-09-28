import Foundation
import Observation
import StoreKit

/// One non-consumable, verified locally by StoreKit 2. No server, no account.
@MainActor
@Observable
final class ProStore {
    static let productID = "app.hearthday.pro"

    enum LoadState: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    private(set) var product: Product?
    private(set) var loadState: LoadState = .loading
    private(set) var isPurchasing = false
    private(set) var isPro = false
    var purchaseMessage: String?

    @ObservationIgnored var onEntitlementChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

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
            product = try await Product.products(for: [Self.productID]).first
            loadState = product == nil
                ? .unavailable("Hearthday Pro isn’t available in your region’s App Store right now.")
                : .ready
        } catch {
            loadState = .unavailable("Couldn’t reach the App Store. Check your connection and try again.")
        }
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    purchaseMessage = "Thank you. Pro is unlocked on this Apple Account."
                } else {
                    purchaseMessage = "The App Store couldn’t verify that purchase. You haven’t been charged twice; try Restore."
                }
            case .pending:
                purchaseMessage = "Your purchase is waiting for approval. Pro unlocks as soon as it goes through."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseMessage = "The purchase didn’t go through. Nothing was charged."
        }
        await refreshEntitlement()
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseMessage = isPro ? "Pro restored." : "No previous Pro purchase was found for this Apple Account."
        } catch {
            purchaseMessage = "Couldn’t reach the App Store to restore. Try again when you’re online."
        }
    }

    private func refreshEntitlement() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Self.productID, t.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
        onEntitlementChange?(owned)
    }
}
