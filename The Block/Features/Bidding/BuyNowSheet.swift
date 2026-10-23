//
//  BuyNowSheet.swift
//  The Block
//
//  Buy Now confirmation sheet: price, fee estimate, binding notice, or the reason
//  Buy Now is unavailable (spec BID-10, BID-11).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Buy Now confirmation sheet (spec BID-10, BID-11, FEES-1, UX-5).
///
/// Shows the price and that buying ends the auction; unavailable lots explain why and offer
/// no confirm button. On success it shows "Purchased by you" briefly, then calls `onFinish`.
struct BuyNowSheet: View {

    /// Bid / Buy Now state for the lot.
    let viewModel: BidViewModel
    /// Closes the sheet: on Cancel or Done, or shortly after a successful purchase.
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Localizable.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.phase == .succeeded {
                    // After success there is nothing to cancel; "Done" makes that clear.
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Localizable.done, action: onFinish)
                            .accessibilityIdentifier("buyNow.doneButton")
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Localizable.cancel, action: onFinish)
                            .disabled(viewModel.isSubmitting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .sensoryFeedback(.success, trigger: viewModel.phase) { _, new in new == .succeeded }
        .sensoryFeedback(.error, trigger: viewModel.rejectionMessage) { _, new in new != nil }
        .task { await viewModel.observeVehicle() }
        .task(id: viewModel.phase) {
            guard viewModel.phase == .succeeded else { return }
            try? await Task.sleep(for: Constants.successDisplayDuration)
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    /// Success, the reason Buy Now is unavailable, or the confirmation (spec BID-11).
    @ViewBuilder
    private var content: some View {
        if viewModel.phase == .succeeded {
            BidSuccessView(
                title: Localizable.successTitle,
                detail: viewModel.vehicle?.yourPurchasePrice.map { Localizable.successDetail(Formatting.currency($0)) },
                identifier: "buyNow.successMessage"
            )
        } else if let reason = viewModel.buyNowUnavailableReason {
            ContentUnavailableView(
                Localizable.unavailableTitle,
                systemImage: "cart.badge.minus",
                description: Text(reason)
            )
            .accessibilityIdentifier("buyNow.unavailableMessage")
        } else {
            confirmation
        }
    }

    /// Price, title, fee estimate, ends-the-auction notice, any rejection, and the confirm button (spec BID-10).
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(Localizable.price)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.vehicle?.buyNowPrice.map { Formatting.currency($0) } ?? "")
                    .font(.largeTitle.monospacedDigit().bold())
                    .accessibilityIdentifier("buyNow.price")
                if let vehicle = viewModel.vehicle {
                    Text(vehicle.title)
                        .font(.headline)
                }
            }
            .accessibilityElement(children: .combine)

            if let estimate = viewModel.buyNowEstimate {
                FeeEstimateView(estimate: estimate, identifierPrefix: "buyNow")
            }

            Label(Localizable.endsAuctionNotice, systemImage: "bolt.fill")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let message = viewModel.rejectionMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("buyNow.validationMessage")
            }

            Button {
                Task { await viewModel.buyNow() }
            } label: {
                ZStack {
                    Text(Localizable.confirm)
                        .opacity(viewModel.isSubmitting ? 0 : 1)
                    if viewModel.isSubmitting {
                        ProgressView()
                            .accessibilityLabel(Localizable.buying)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("buyNow.confirmButton")
        }
    }

}

private enum Constants {
    static let successDisplayDuration: Duration = .seconds(1.2)
}

private enum Localizable {
    static let title = "Buy Now"
    static let cancel = "Cancel"
    static let done = "Done"
    static let price = "Buy Now price"
    static let endsAuctionNotice = "Buying ends the auction immediately. The purchase is binding."
    static let confirm = "Confirm purchase"
    static let buying = "Completing purchase"
    static let unavailableTitle = "Buy Now unavailable"
    static let successTitle = "Purchased by you"

    static func successDetail(_ price: String) -> String { "You bought this vehicle for \(price)." }
}
