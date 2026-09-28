import SwiftUI
import StoreKit
import HearthdayCore

/// A plain, honest offer: one price, paid once, and a clear list of what stays free.
struct ProView: View {
    @Environment(ProStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Hearthday Pro").font(Typo.display())
                    Text("Plans that learn your kitchen.").font(.title3).foregroundStyle(Palette.ash)

                    VStack(alignment: .leading, spacing: 14) {
                        Feature(icon: "chart.line.uptrend.xyaxis", title: "Personal timing", text: "Your logged bakes adjust future plans and narrow the likely-ready window.")
                        Feature(icon: "square.stack", title: "Unlimited formulas", text: "Free includes \(AppState.freeFormulaLimit).")
                        Feature(icon: "book", title: "Full journal", text: "Free shows your last \(AppState.freeHistoryLimit) bakes; older ones are kept, never deleted.")
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Always free").font(.headline)
                        Text("Planning around your busy times, live check-ins and re-planning, reminders, and seeing what calibration has learned.")
                            .foregroundStyle(Palette.ash)
                    }

                    purchaseArea

                    if let message = store.purchaseMessage {
                        Text(message).font(.callout).foregroundStyle(Palette.rye)
                            .accessibilityIdentifier("pro.message")
                    }

                    Button {
                        Task { await store.restore() }
                    } label: {
                        if store.isRestoring { ProgressView() } else { Text("Restore purchase") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(store.isRestoring || store.isPurchasing)
                    .accessibilityIdentifier("pro.restore")
                    Text("One-time purchase. No subscription, no trial that turns into a charge. Family Sharing supported.")
                        .font(.footnote).foregroundStyle(Palette.ash)
                }
                .padding()
            }
            .background(Palette.flour.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @ViewBuilder
    private var purchaseArea: some View {
        if model.state.isPro || store.isPro {
            Label("Pro is unlocked", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(Palette.sage)
                .accessibilityIdentifier("pro.unlocked")
        } else {
            switch store.loadState {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 52)
            case .unavailable(let reason):
                VStack(spacing: 10) {
                    Text(reason).font(.callout).foregroundStyle(Palette.ash)
                        .accessibilityIdentifier("pro.unavailable")
                    Button("Try again") { Task { await store.loadProduct() } }.buttonStyle(SecondaryButtonStyle())
                }
            case .ready:
                if let product = store.product {
                    Button {
                        Task { await store.purchase() }
                    } label: {
                        if store.isPurchasing { ProgressView().tint(.white) } else { Text("Unlock for \(product.displayPrice)") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.isPurchasing || store.isRestoring)
                    .accessibilityIdentifier("pro.buy")
                }
            }
        }
    }
}

private struct Feature: View {
    var icon: String
    var title: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.crust).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.rye)
                Text(text).font(.subheadline).foregroundStyle(Palette.ash)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
