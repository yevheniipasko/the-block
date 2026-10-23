//
//  AuctionStatus.swift
//  The Block
//
//  Auction status, ended-outcome, and floor-state value types.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation

/// Where a vehicle's auction is at a given moment (spec TIME-2).
enum AuctionStatus: Hashable, Sendable {

    case upcoming(startsAt: Date)
    case active(endsAt: Date)
    case ended(EndedOutcome)

    /// Whether the auction has ended, whatever the outcome.
    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }

}

/// How an ended auction finished, from the buyer's point of view (spec Assumptions: Ended outcomes).
enum EndedOutcome: Hashable, Sendable {
    /// Bought through Buy Now, or won as high bidder with the floor met.
    case purchasedByYou
    /// Someone else won with the floor met (or no floor).
    case sold
    /// Highest bid stayed below the floor; the seller decides (not simulated).
    case pendingBelowFloor
    /// The auction ended without bids.
    case noSale
}

/// Whether the current bid reaches the seller's floor (reserve) price.
/// The floor amount itself is never shown to the buyer.
enum FloorState: Hashable, Sendable {
    case noFloor
    case met
    case notMet
}

extension VehicleModel {

    /// Whether the current bid meets the floor (`reservePrice`); `.noFloor` when the lot has none.
    ///
    /// A lot with a floor but no bids is `.notMet`; a Buy Now purchase meets it, since the lot is
    /// sold. Shown in the header (spec DETAIL-2) and recomputed after the buyer bids or buys
    /// (spec BID-6, BID-10).
    var floorState: FloorState {
        guard let reservePrice else { return .noFloor }
        guard !isPurchasedByYou else { return .met }
        guard let currentBid, currentBid >= reservePrice else { return .notMet }
        return .met
    }

    /// Auction status at `now` (spec TIME-2).
    ///
    /// Upcoming before `auctionStart`, active until `auctionEnd` (start + 72 h), ended after that.
    /// A Buy Now purchase ends the lot immediately as `.purchasedByYou`, whatever the time (spec BID-10).
    ///
    /// - Parameter now: The moment to evaluate, normally `AuctionClockProtocol.now`.
    func status(at now: Date) -> AuctionStatus {
        if isPurchasedByYou {
            return .ended(.purchasedByYou)
        }
        if now < auctionStart {
            return .upcoming(startsAt: auctionStart)
        }
        if now < auctionEnd {
            return .active(endsAt: auctionEnd)
        }
        return .ended(endedOutcome)
    }

    /// Outcome of a lot whose time has run out (spec TIME-2, Assumptions: Ended outcomes).
    ///
    /// No bids → no sale; floor not met → pending below floor; otherwise purchased by you
    /// when you are the high bidder, else sold.
    private var endedOutcome: EndedOutcome {
        guard bidCount > 0 else { return .noSale }
        guard floorState != .notMet else { return .pendingBelowFloor }
        return isYouHighBidder ? .purchasedByYou : .sold
    }

}
