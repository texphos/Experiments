import XCTest
import StoreKit
import StoreKitTest
@testable import Hearthday

/// Runs real StoreKit 2 calls against the local `Hearthday.storekit` configuration. No App Store account or
/// network is involved, and nothing here can unlock Pro in a shipped build.
@MainActor
final class ProStoreTests: XCTestCase {
    var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Hearthday")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
    }

    func testLoadsTheProductWithItsLocalPrice() async throws {
        let store = ProStore()
        await store.start()
        XCTAssertEqual(store.loadState, .ready)
        let product = try XCTUnwrap(store.product)
        XCTAssertEqual(product.id, ProStore.defaultProductID)
        XCTAssertEqual(product.type, .nonConsumable)
        XCTAssertEqual(product.price, Decimal(string: "9.99"))
        XCTAssertFalse(store.isPro)
    }

    func testVerifiedPurchaseUnlocksProAndNotifiesTheApp() async throws {
        let store = ProStore()
        var reported: [Bool] = []
        store.onEntitlementChange = { reported.append($0) }
        await store.start()
        await store.purchase()
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(reported.last, true)
        XCTAssertEqual(store.purchaseMessage, "Thank you. Pro is unlocked on this Apple Account.")
    }

    func testFailedPurchaseDoesNotUnlockOrClaimSuccess() async throws {
        session.failTransactionsEnabled = true
        let store = ProStore()
        await store.start()
        await store.purchase()
        XCTAssertFalse(store.isPro)
        let message = try XCTUnwrap(store.purchaseMessage)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("unlocked on"), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("thank you"), message)
    }

    func testAskToBuyIsPendingNotUnlocked() async throws {
        session.askToBuyEnabled = true
        let store = ProStore()
        await store.start()
        await store.purchase()
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.purchaseMessage, "Your purchase is waiting for approval. Pro unlocks as soon as it goes through.")
    }

    func testRestoreWithNoPurchaseDoesNotUnlock() async throws {
        let store = ProStore()
        await store.start()
        await store.restore()
        XCTAssertFalse(store.isPro)
        XCTAssertNotEqual(store.purchaseMessage, "Pro restored.")
    }

    func testExistingPurchaseIsRecognisedOnLaunch() async throws {
        let first = ProStore()
        await first.start()
        await first.purchase()
        XCTAssertTrue(first.isPro)

        let relaunched = ProStore()
        await relaunched.start()
        XCTAssertTrue(relaunched.isPro, "currentEntitlements survives a relaunch")
    }

    func testRefundRevokesPro() async throws {
        let store = ProStore()
        await store.start()
        await store.purchase()
        XCTAssertTrue(store.isPro)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        // The test session applies the refund asynchronously; allow it a few seconds to reach currentEntitlements.
        for _ in 0..<20 where store.isPro {
            try await Task.sleep(for: .milliseconds(250))
            await store.refreshEntitlement()
        }
        XCTAssertFalse(store.isPro, "A refunded purchase no longer unlocks Pro")
    }

    func testMissingProductShowsAnExplicitUnavailableState() async throws {
        let store = ProStore(productID: "app.hearthday.does-not-exist")
        await store.start()
        guard case .unavailable(let reason) = store.loadState else { return XCTFail("\(store.loadState)") }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertNil(store.product)
        await store.purchase()
        XCTAssertFalse(store.isPro, "No product, no purchase")
    }
}
