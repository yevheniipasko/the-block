//
//  BiddingRules.swift
//  The Block
//
//  Pure bidding rules: activity levels, adaptive step, minimum next bid, bid
//  validation, and Buy Now eligibility.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

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

    /// Buckets a bid count into an activity level (spec BID-9): 0 opening, 1–3 quiet, 4–9 active, 10+ hot.
    ///
    /// Negative counts are treated as opening.
    init(bidCount: Int) {
        switch bidCount {
        case ...0: self = .opening
        case 1...3: self = .quiet
        case 4...9: self = .active
        default: self = .hot
        }
    }

}

/// Why a bid or Buy Now was refused; the repository leaves the lot unchanged in every case (spec BID-8).
enum BidRejection: Error, Hashable, Sendable {
    /// The lot's auction has ended (spec BID-7).
    case auctionEnded
    /// The amount is below the minimum next bid (spec BID-3).
    case belowMinimum(minimum: Int)
    /// The amount reaches the Buy Now price; the buyer should use Buy Now (spec BID-4).
    case atOrAboveBuyNow(buyNowPrice: Int)
    /// Buy Now is not offered on this lot right now (spec BID-11).
    case buyNowUnavailable
    /// The lot is not in the inventory.
    case vehicleNotFound
    /// The request never reached the server (network / feed error).
    case connectionFailed
}

/// Pure auction rules (spec BID-1, BID-3, BID-4, BID-7, BID-9, BID-11).
enum BiddingRules {

    /// Price-tier step before the activity multiplier (spec BID-9).
    ///
    /// $200 below $10,000, $500 from $10,000 to $29,999, $1,000 from $30,000.
    ///
    /// - Parameter currentBid: Current bid in whole CAD dollars.
    static func baseStep(forCurrentBid currentBid: Int) -> Int {
        switch currentBid {
        case ..<10_000: 200
        case ..<30_000: 500
        default: 1_000
        }
    }

    /// Adaptive bid step: price-tier base × activity multiplier (spec BID-9).
    ///
    /// Quiet lots halve the base, hot lots double it; opening and active lots use the base as is.
    ///
    /// - Returns: The increment above `currentBid`, in whole CAD dollars.
    static func step(currentBid: Int, bidCount: Int) -> Int {
        let base = baseStep(forCurrentBid: currentBid)
        switch ActivityLevel(bidCount: bidCount) {
        case .opening, .active: return base
        case .quiet: return base / 2
        case .hot: return base * 2
        }
    }

    /// Minimum amount the next bid must reach for this lot (spec BID-1, BID-3).
    ///
    /// The starting bid when there are no bids yet; otherwise the current bid plus the adaptive step.
    ///
    /// - Returns: Minimum valid next bid in whole CAD dollars.
    static func minimumNextBid(for vehicle: VehicleModel) -> Int {
        guard let currentBid = vehicle.currentBid, vehicle.bidCount > 0 else {
            return vehicle.startingBid
        }
        return currentBid + step(currentBid: currentBid, bidCount: vehicle.bidCount)
    }

    /// Checks whether `amount` is a valid bid on `vehicle` at `now`.
    ///
    /// Rejects, in order: ended lots (spec BID-7), amounts below the minimum next bid (spec BID-3),
    /// and amounts at or above the Buy Now price (spec BID-4). Upcoming lots accept bids
    /// (pre-sale bidding, per spec Assumptions).
    ///
    /// - Returns: `.success` when the bid can be placed, otherwise the first rejection that applies.
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

    /// Whether Buy Now is offered for `vehicle` at `now` (spec BID-10, BID-11).
    ///
    /// Only active lots with a Buy Now price qualify; upcoming and ended lots never do.
    static func canBuyNow(_ vehicle: VehicleModel, at now: Date) -> Bool {
        guard vehicle.buyNowPrice != nil else { return false }
        if case .active = vehicle.status(at: now) { return true }
        return false
    }

}
