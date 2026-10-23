//
//  BidPosition.swift
//  The Block
//
//  The buyer's position on a lot (winning, outbid, won, bought, lost) and how
//  it is derived from the vehicle's state.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation

/// The buyer's standing on a lot they bid on or bought (spec MYBIDS-2, ALERT-1).
enum BidPosition: Hashable, Sendable, CaseIterable {
    /// High bidder on a lot that hasn't ended.
    case winning
    /// Bid on a lot that hasn't ended, but someone else holds the high bid.
    case outbid
    /// The auction ended as "Purchased by you" through bidding.
    case won
    /// Bought through Buy Now.
    case bought
    /// The auction ended any other way (sold to someone else, pending below floor).
    case lost
}

extension VehicleModel {

    /// The buyer's position on this lot at `now`, or `nil` if they never bid on or bought it.
    func bidPosition(at now: Date) -> BidPosition? {
        if isPurchasedByYou {
            return .bought
        }
        guard yourBid != nil else { return nil }
        if case .ended(let outcome) = status(at: now) {
            return outcome == .purchasedByYou ? .won : .lost
        }
        return isYouHighBidder ? .winning : .outbid
    }

}
