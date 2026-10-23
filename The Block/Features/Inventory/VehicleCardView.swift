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

        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(Localizable.lot(vehicle.lot))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(Constants.lotTracking)
                Spacer(minLength: Spacing.small)
                AuctionStatusBadge(vehicle: vehicle, pausedAt: countdownPausedAt)
            }
            layout {
                photo(isStacked: isStacked)
                details
            }
        }
        .padding(Spacing.medium)
        .background(.background, in: .rect(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(.quaternary)
        }
        .contentShape(.rect(cornerRadius: CornerRadius.medium))
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

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(vehicle.title)
                .font(.headline)
                .lineLimit(Constants.titleLineLimit)
            priceLine
            Text(odometerAndLocation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let buyNowPrice = vehicle.buyNowPrice {
                Label(Localizable.buyNow(Formatting.currency(buyNowPrice)), systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(Color.accentColor.opacity(Constants.badgeOpacity), in: Capsule())
            }
            yourPositionMarker
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
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

    private var bidCountText: some View {
        Text(InventoryLabels.bidCount(vehicle.bidCount))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Your position on the lot: purchased, high bidder, or outbid (spec BID-6, BID-10, LIVE-3).
    @ViewBuilder private var yourPositionMarker: some View {
        if let purchasePrice = vehicle.yourPurchasePrice {
            Label(Localizable.purchased(Formatting.currency(purchasePrice)), systemImage: "bag.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("list.purchasedBadge")
        } else if vehicle.isYouHighBidder {
            Label(Localizable.highBidder, systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("list.highBidderBadge")
        } else if vehicle.isYouOutbid {
            Label(Localizable.outbid, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier("list.outbidBadge")
        }
    }

    private var price: Int {
        vehicle.currentBid ?? vehicle.startingBid
    }

    private var priceTitle: String {
        vehicle.currentBid == nil ? Localizable.startingAt : Localizable.currentBid
    }

    private var odometerAndLocation: String {
        "\(Formatting.kilometres(vehicle.odometerKm)) · \(vehicle.city), \(vehicle.province)"
    }

    /// VoiceOver summary: title, price and bids, status, Buy Now, your position (spec UX-3).
    private var accessibilityLabel: String {
        var parts = [
            vehicle.title,
            Localizable.lot(vehicle.lot),
            "\(priceTitle) \(Formatting.currency(price)), \(InventoryLabels.bidCount(vehicle.bidCount))",
            odometerAndLocation,
            vehicle.status(at: now).badgeTitle
        ]
        if let buyNowPrice = vehicle.buyNowPrice {
            parts.append(Localizable.buyNow(Formatting.currency(buyNowPrice)))
        }
        if let purchasePrice = vehicle.yourPurchasePrice {
            parts.append(Localizable.purchased(Formatting.currency(purchasePrice)))
        } else if vehicle.isYouHighBidder {
            parts.append(Localizable.highBidder)
        } else if vehicle.isYouOutbid {
            parts.append(Localizable.outbid)
        }
        return parts.joined(separator: ". ")
    }

}

private enum Constants {
    static let thumbnailWidth: CGFloat = 112
    static let thumbnailHeight: CGFloat = 84
    static let stackedPhotoHeight: CGFloat = 180
    static let titleLineLimit = 2
    static let badgeOpacity = 0.12
    static let lotTracking: CGFloat = 0.8
}

private enum Localizable {
    static let currentBid = "Current bid"
    static let startingAt = "Starting at"
    static let highBidder = "You're the high bidder"
    static let outbid = "You've been outbid"
    static func lot(_ lot: String) -> String { "LOT \(lot)" }
    static func buyNow(_ price: String) -> String { "Buy Now \(price)" }
    static func purchased(_ price: String) -> String { "Purchased by you for \(price)" }
}
