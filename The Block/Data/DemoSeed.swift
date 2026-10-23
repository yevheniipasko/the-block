//
//  DemoSeed.swift
//  The Block
//
//  Seeds one leading and one outbid demo position into the launch snapshot.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation

/// Gives the buyer two positions at launch so "My bids" and the outbid state are visible
/// without setup (spec MYBIDS-7, Assumptions: demo seed). Demo data, called out in the README.
enum DemoSeed {

    /// Marks the buyer as leading on the first eligible lot and outbid on the second.
    ///
    /// Eligible: active at `now`, already has bids, and its next minimum stays below any Buy Now
    /// price (so the market can keep bidding on it). Lots are taken in lot-number order, so the
    /// choice is stable across launches. Lots without bids are never touched.
    static func apply(to vehicles: [VehicleModel], now: Date) -> [VehicleModel] {
        let eligible = vehicles
            .filter { isEligible($0, now: now) }
            .sorted { $0.lot < $1.lot }
            .prefix(2)
            .map(\.id)
        guard let leadingID = eligible.first else { return vehicles }
        let outbidID = eligible.dropFirst().first

        return vehicles.map { vehicle in
            var copy = vehicle
            if vehicle.id == leadingID {
                copy.yourBid = vehicle.currentBid
            } else if vehicle.id == outbidID, let currentBid = vehicle.currentBid {
                let step = BiddingRules.step(currentBid: currentBid, bidCount: vehicle.bidCount)
                copy.yourBid = max(vehicle.startingBid, currentBid - step)
            }
            return copy
        }
    }

    /// Whether a lot can carry a seeded position: active, has bids, and still biddable below Buy Now.
    private static func isEligible(_ vehicle: VehicleModel, now: Date) -> Bool {
        guard case .active = vehicle.status(at: now), vehicle.bidCount > 0, vehicle.currentBid != nil else {
            return false
        }
        guard let buyNowPrice = vehicle.buyNowPrice else { return true }
        return BiddingRules.minimumNextBid(for: vehicle) < buyNowPrice
    }

}
