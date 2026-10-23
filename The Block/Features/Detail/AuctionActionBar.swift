//
//  AuctionActionBar.swift
//  The Block
//
//  Pinned bottom bar on the detail screen: Place bid / Buy Now buttons, or the
//  outcome once the lot has ended (spec DETAIL-6).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Bottom action bar: place bid / Buy Now, or the outcome once ended (spec DETAIL-6, TIME-4).
///
/// Re-evaluates on every tick of the shared `AuctionTicker`, so the buttons flip when the
/// auction starts or ends while the screen is open.
struct AuctionActionBar: View {

    /// Source of the bar's state for the current moment.
    let viewModel: VehicleDetailViewModel
    /// Asks the router to present the bid sheet.
    let onPlaceBid: () -> Void
    /// Asks the router to present the Buy Now sheet.
    let onBuyNow: () -> Void

    /// Shared once-per-second clock; each tick re-evaluates the bar.
    @Environment(AuctionTicker.self) private var ticker

    var body: some View {
        if let state = viewModel.actionBar(at: ticker.now) {
            content(for: state)
                .padding(.horizontal, Spacing.large)
                .padding(.vertical, Spacing.medium)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    /// Bid / Buy Now buttons for live lots, or the outcome label for ended ones.
    @ViewBuilder
    private func content(for state: DetailActionBarState) -> some View {
        switch state {
        case .bidding(let minimumBid, let buyNowPrice):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.medium) { buttons(minimumBid: minimumBid, buyNowPrice: buyNowPrice) }
                VStack(spacing: Spacing.small) { buttons(minimumBid: minimumBid, buyNowPrice: buyNowPrice) }
            }
        case .ended(let outcome):
            Label(outcome.title, systemImage: outcome == .purchasedByYou ? "checkmark.seal.fill" : "flag.checkered")
                .font(.headline)
                .foregroundStyle(outcome.tint)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Localizable.outcomeAccessibility(outcome.title))
                .accessibilityIdentifier("detail.outcome")
        }
    }

    /// "Place bid · Min $X" plus "Buy Now $X" when offered; laid out by the caller.
    @ViewBuilder
    private func buttons(minimumBid: Int, buyNowPrice: Int?) -> some View {
        Button(action: onPlaceBid) {
            Text(Localizable.placeBid(Formatting.currency(minimumBid)))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel(Localizable.placeBidAccessibility(Formatting.currency(minimumBid)))
        .accessibilityIdentifier("detail.placeBidButton")

        if let buyNowPrice {
            Button(action: onBuyNow) {
                Text(Localizable.buyNow(Formatting.currency(buyNowPrice)))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("detail.buyNowButton")
        }
    }

}

private enum Localizable {
    static func placeBid(_ minimum: String) -> String { "Place bid · Min \(minimum)" }
    static func placeBidAccessibility(_ minimum: String) -> String { "Place bid, minimum \(minimum)" }
    static func buyNow(_ price: String) -> String { "Buy Now \(price)" }
    static func outcomeAccessibility(_ title: String) -> String { "Auction ended: \(title)" }
}
