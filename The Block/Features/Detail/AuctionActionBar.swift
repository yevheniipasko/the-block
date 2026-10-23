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

    /// "Place bid / Min $X" plus "Buy Now / $X" when offered; laid out by the caller.
    ///
    /// Both buttons use the same two-line label (action, then price) so they stay the same
    /// height side by side; the filled style alone marks Place bid as the primary action.
    @ViewBuilder
    private func buttons(minimumBid: Int, buyNowPrice: Int?) -> some View {
        Button(action: onPlaceBid) {
            label(title: Localizable.placeBid, price: Localizable.minimum(Formatting.currency(minimumBid)))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel(Localizable.placeBidAccessibility(Formatting.currency(minimumBid)))
        .accessibilityIdentifier("detail.placeBidButton")

        if let buyNowPrice {
            Button(action: onBuyNow) {
                label(title: Localizable.buyNow, price: Formatting.currency(buyNowPrice))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel(Localizable.buyNowAccessibility(Formatting.currency(buyNowPrice)))
            .accessibilityIdentifier("detail.buyNowButton")
        }
    }

    /// Two-line button label: action on top, price below, each kept on one line.
    ///
    /// The fixed horizontal size makes `ViewThatFits` stack the buttons instead of
    /// truncating or wrapping a label when they don't fit side by side.
    private func label(title: String, price: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
            Text(price)
                .font(.subheadline)
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
    }

}

private enum Localizable {
    static let placeBid = "Place bid"
    static let buyNow = "Buy Now"
    static func minimum(_ amount: String) -> String { "Min \(amount)" }
    static func placeBidAccessibility(_ minimum: String) -> String { "Place bid, minimum \(minimum)" }
    static func buyNowAccessibility(_ price: String) -> String { "Buy Now for \(price)" }
    static func outcomeAccessibility(_ title: String) -> String { "Auction ended: \(title)" }
}
