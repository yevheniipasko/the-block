import SwiftUI

/// Place-bid sheet (spec BID-1 … BID-9).
///
/// Shell placeholder — the Bidding feature replaces the body. Keep the `init` signature:
/// call `onFinish` to dismiss.
struct BidSheet: View {

    let viewModel: BidViewModel
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            Text(viewModel.vehicle?.title ?? "")
                .navigationTitle("Place bid")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onFinish)
                    }
                }
        }
    }

}

/// Buy Now confirmation sheet (spec BID-10, BID-11).
///
/// Shell placeholder — the Bidding feature replaces the body. Keep the `init` signature.
struct BuyNowSheet: View {

    let viewModel: BidViewModel
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            Text(viewModel.vehicle?.title ?? "")
                .navigationTitle("Buy Now")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onFinish)
                    }
                }
        }
    }

}
