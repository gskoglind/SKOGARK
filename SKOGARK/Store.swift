//
//  Store.swift
//  SKOGARK
//
//  The Round-the-World Ticket: a single non-consumable purchase that unlocks
//  every premium destination — Japan, London, Sydney, and all destinations
//  still to come. Explore and Savannah are free forever. StoreKit 2; the
//  web app is unaffected and stays free.
//

import StoreKit
import SwiftUI

@Observable @MainActor
final class Store {
    /// The one product. Must match the in-app purchase configured in
    /// App Store Connect (non-consumable, Family Sharing on).
    static let ticketID = "com.gskoglind.skogark.roundtheworld"

    /// Destinations playable without the ticket.
    static let freeDestinations: Set<String> = ["Explore", "Savannah"]

    private(set) var hasTicket = false
    private(set) var ticket: Product?
    private var updatesTask: Task<Void, Never>?

    init() {
        // Unlocks everything for the screenshot rig and UI tests.
        if ProcessInfo.processInfo.arguments.contains("-unlockAll") {
            hasTicket = true
        }
        updatesTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    func isUnlocked(_ destination: String) -> Bool {
        hasTicket || Self.freeDestinations.contains(destination)
    }

    /// Loads the product and re-checks the entitlement. Writes observable
    /// state only on real changes, so the UI doesn't rebuild needlessly.
    func refresh() async {
        let loaded = try? await Product.products(for: [Self.ticketID]).first
        if loaded?.id != ticket?.id { ticket = loaded }
        await refreshEntitlement()
    }

    func purchase() async {
        guard let ticket else { return }
        guard let result = try? await ticket.purchase() else { return }
        if case .success(.verified(let transaction)) = result {
            hasTicket = true
            await transaction.finish()
        }
    }

    /// "Restore Purchases" — required by App Review for non-consumables.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.ticketID,
               transaction.revocationDate == nil,
               !hasTicket {
                hasTicket = true
            }
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result,
               transaction.productID == Self.ticketID {
                if transaction.revocationDate == nil { hasTicket = true }
                await transaction.finish()
            }
        }
    }
}

/// The sheet shown when a locked destination is tapped.
struct PaywallView: View {
    let store: Store
    let destination: String
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🎟")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("The Round-the-World Ticket")
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("\(destination) is a premium destination. One ticket unlocks Japan, London, and Sydney — and every destination still to come. Yours forever, on all your devices.")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                purchasing = true
                Task {
                    await store.purchase()
                    purchasing = false
                    if store.hasTicket { dismiss() }
                }
            } label: {
                Text(purchasing ? "One moment…"
                     : "Buy the Ticket\(store.ticket.map { " · \($0.displayPrice)" } ?? "")")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(purchasing || store.ticket == nil)
            .padding(.horizontal)

            Button("Restore Purchases") {
                Task {
                    await store.restore()
                    if store.hasTicket { dismiss() }
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.green)

            Button("Maybe later") { dismiss() }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))

            Spacer()
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task { await store.refresh() }
    }
}
