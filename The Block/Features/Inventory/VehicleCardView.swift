//
//  VehicleCardView.swift
//  The Block
//
//  Inventory row card: photo, title, price, bids, odometer, location,
//  auction status, Buy Now, and your bid position.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// One inventory row: photo, title, price, bids, odometer, location, status, Buy Now, and
/// your own position on the lot (spec LIST-1, BID-6, LIVE-3, UX-2, UX-3).
///
/// Lays out photo and details side by side; at accessibility text sizes the photo moves
/// above the details so nothing clips.
struct VehicleCardView: View {

    let vehicle: VehicleModel
    /// Moment used for the VoiceOver status; the visible badge keeps its own live clock.
    let now: Date
    /// When set, the countdown stays at this moment until scrolling ends.
    var countdownPausedAt: Date?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.medium))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.medium))

        layout {
            photo(isStacked: isStacked)
            details
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// First photo as a thumbnail, or full width when the card is stacked.
    private func photo(isStacked: Bool) -> some View {
        VehicleImage(url: vehicle.images.first)
            .frame(
                width: isStacked ? nil : Constants.thumbnailWidth,
                height: isStacked ? Constants.stackedPhotoHeight : Constants.thumbnailHeight
            )
            .frame(maxWidth: isStacked ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    /// Title, price line, odometer and location, status badge, Buy Now price, and your position.
    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(vehicle.title)
                .font(.headline)
                .lineLimit(Constants.titleLineLimit)
            priceLine
            Text(odometerAndLocation)
                .font(.caption)
                .foregroundStyle(.secondary)
            AuctionStatusBadge(vehicle: vehicle, pausedAt: countdownPausedAt)
            if let buyNowPrice = vehicle.buyNowPrice {
                Label(Localizable.buyNow(Formatting.currency(buyNowPrice)), systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            CardPositionMarker(vehicle: vehicle, pausedAt: countdownPausedAt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Price title, amount, and bid count on one line when they fit; otherwise stacked, so the
    /// amount never wraps mid-number in a narrow sidebar or at accessibility text sizes (spec UX-1, UX-2).
    private var priceLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                priceTitleText
                priceAmountText
                bidCountText
            }
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                priceTitleText
                priceAmountText
                bidCountText
            }
        }
    }

    private var priceTitleText: some View {
        Text(priceTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var priceAmountText: some View {
        Text(Formatting.currency(price))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

    private var bidCountText: some View {
        Text(Formatting.bidCount(vehicle.bidCount))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Current bid, or the starting bid while there are no bids.
    private var price: Int {
        vehicle.currentBid ?? vehicle.startingBid
    }

    /// `Current bid` or `Starting at`, matching `price`.
    private var priceTitle: String {
        vehicle.currentBid == nil ? Localizable.startingAt : Localizable.currentBid
    }

    /// Odometer and location, e.g. `47,731 km · Mississauga, Ontario`.
    private var odometerAndLocation: String {
        "\(Formatting.kilometres(vehicle.odometerKm)) · \(vehicle.city), \(vehicle.province)"
    }

    /// VoiceOver summary: title, price and bids, status, Buy Now, your position (spec UX-3).
    private var accessibilityLabel: String {
        var parts = [
            vehicle.title,
            "\(priceTitle) \(Formatting.currency(price)), \(Formatting.bidCount(vehicle.bidCount))",
            vehicle.status(at: now).badgeTitle
        ]
        if let buyNowPrice = vehicle.buyNowPrice {
            parts.append(Localizable.buyNow(Formatting.currency(buyNowPrice)))
        }
        switch CardBuyerPosition(vehicle: vehicle, at: now) {
        case .purchased(let price): parts.append(Localizable.purchased(Formatting.currency(price)))
        case .highBidder: parts.append(Localizable.highBidder)
        case .outbid: parts.append(Localizable.outbid)
        case nil: break
        }
        return parts.joined(separator: ". ")
    }

}

/// The buyer's own position shown on an inventory card (spec BID-6, BID-10, LIVE-3).
enum CardBuyerPosition: Equatable {
    /// Bought through Buy Now for this price.
    case purchased(Int)
    /// The buyer's bid is the current bid.
    case highBidder
    /// Someone passed the buyer's bid on a lot that is still open.
    case outbid

    /// Picks the marker for `vehicle` at `now`, or `nil` when the buyer has no position to show.
    ///
    /// "Outbid" is hidden once the lot has ended: it is no longer actionable and the status
    /// badge shows the outcome instead (same rule as the detail header).
    init?(vehicle: VehicleModel, at now: Date) {
        if let purchasePrice = vehicle.yourPurchasePrice {
            self = .purchased(purchasePrice)
        } else if vehicle.isYouHighBidder {
            self = .highBidder
        } else if vehicle.isYouOutbid, !vehicle.status(at: now).isEnded {
            self = .outbid
        } else {
            return nil
        }
    }
}

/// Your position on the lot: purchased, high bidder, or outbid (spec BID-6, BID-10, LIVE-3).
///
/// Its own view so only this line, not the whole card, re-renders on each tick of the shared
/// clock that hides "outbid" when the lot ends.
private struct CardPositionMarker: View {

    let vehicle: VehicleModel
    /// When set, the marker is evaluated at this moment until scrolling ends, like the badge.
    var pausedAt: Date?

    @Environment(AuctionTicker.self) private var ticker

    var body: some View {
        switch CardBuyerPosition(vehicle: vehicle, at: pausedAt ?? ticker.now) {
        case .purchased(let price):
            Label(Localizable.purchased(Formatting.currency(price)), systemImage: "bag.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("list.purchasedBadge")
        case .highBidder:
            Label(Localizable.highBidder, systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("list.highBidderBadge")
        case .outbid:
            Label(Localizable.outbid, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier("list.outbidBadge")
        case nil:
            EmptyView()
        }
    }

}

/// Layout constants for the inventory card.
private enum Constants {
    static let thumbnailWidth: CGFloat = 112
    static let thumbnailHeight: CGFloat = 84
    static let stackedPhotoHeight: CGFloat = 180
    static let titleLineLimit = 2
}

/// User-facing strings for the inventory card.
private enum Localizable {
    static let currentBid = "Current bid"
    static let startingAt = "Starting at"
    static let highBidder = "You're the high bidder"
    static let outbid = "You've been outbid"
    static func buyNow(_ price: String) -> String { "Buy Now \(price)" }
    static func purchased(_ price: String) -> String { "Purchased by you for \(price)" }
}
