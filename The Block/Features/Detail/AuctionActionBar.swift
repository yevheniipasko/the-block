import SwiftUI

/// Bottom action bar: place bid / Buy Now, or the outcome once ended (spec DETAIL-6, TIME-4).
///
/// Re-evaluates every second through `TimelineView`, so the buttons flip when the auction
/// starts or ends while the screen is open.
struct AuctionActionBar: View {

    let viewModel: VehicleDetailViewModel
    let onPlaceBid: () -> Void
    let onBuyNow: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let state = viewModel.actionBar(at: context.date) {
                content(for: state)
                    .padding(.horizontal, Spacing.large)
                    .padding(.vertical, Spacing.medium)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

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
