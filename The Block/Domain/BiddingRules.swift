import Foundation

/// How busy bidding on a lot is, judged by bid count (the data has no bidder IDs or bid times).
enum ActivityLevel: Hashable, Sendable {

    /// No bids yet; the first bid opens at the starting bid.
    case opening
    /// 1–3 bids.
    case quiet
    /// 4–9 bids.
    case active
    /// 10+ bids.
    case hot

    init(bidCount: Int) {
        switch bidCount {
        case ...0: self = .opening
        case 1...3: self = .quiet
        case 4...9: self = .active
        default: self = .hot
        }
    }

}

enum BidRejection: Error, Hashable, Sendable {
    case auctionEnded
    case belowMinimum(minimum: Int)
    case atOrAboveBuyNow(buyNowPrice: Int)
    case buyNowUnavailable
    case vehicleNotFound
}

/// Pure auction rules (spec BID-1, BID-3, BID-4, BID-7, BID-9, BID-11).
enum BiddingRules {

    /// Step for the current price before the activity multiplier.
    static func baseStep(forCurrentBid currentBid: Int) -> Int {
        switch currentBid {
        case ..<10_000: 200
        case ..<30_000: 500
        default: 1_000
        }
    }

    /// Adaptive step = price base × activity multiplier (quiet ½, active 1×, hot 2×).
    static func step(currentBid: Int, bidCount: Int) -> Int {
        let base = baseStep(forCurrentBid: currentBid)
        switch ActivityLevel(bidCount: bidCount) {
        case .opening, .active: return base
        case .quiet: return base / 2
        case .hot: return base * 2
        }
    }

    static func minimumNextBid(for vehicle: VehicleModel) -> Int {
        guard let currentBid = vehicle.currentBid, vehicle.bidCount > 0 else {
            return vehicle.startingBid
        }
        return currentBid + step(currentBid: currentBid, bidCount: vehicle.bidCount)
    }

    /// Checks a bid amount; upcoming lots accept bids (pre-sale bidding), ended lots don't.
    static func validateBid(_ amount: Int, on vehicle: VehicleModel, at now: Date) -> Result<Void, BidRejection> {
        if vehicle.status(at: now).isEnded {
            return .failure(.auctionEnded)
        }
        let minimum = minimumNextBid(for: vehicle)
        if amount < minimum {
            return .failure(.belowMinimum(minimum: minimum))
        }
        if let buyNowPrice = vehicle.buyNowPrice, amount >= buyNowPrice {
            return .failure(.atOrAboveBuyNow(buyNowPrice: buyNowPrice))
        }
        return .success(())
    }

    /// Buy Now is offered only while the auction is active and the lot has a price.
    static func canBuyNow(_ vehicle: VehicleModel, at now: Date) -> Bool {
        guard vehicle.buyNowPrice != nil else { return false }
        if case .active = vehicle.status(at: now) { return true }
        return false
    }

}
