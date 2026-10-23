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
    /// Eligible: already has bids and can take another one (`BiddingRules.canTakeAnotherBid`), so
    /// the market can keep bidding on it. The outbid lot must also leave room for a bid strictly
    /// below the current bid but at or above the starting bid. Lots are taken in lot-number order,
    /// so the choice is stable across launches. Lots without bids are never touched.
    static func apply(to vehicles: [VehicleModel], now: Date) -> [VehicleModel] {
        let eligible = vehicles
            .filter { isEligible($0, now: now) }
            .sorted { $0.lot < $1.lot }
        guard let leading = eligible.first else { return vehicles }
        let outbid = eligible.dropFirst().first { outbidAmount(for: $0) != nil }

        return vehicles.map { vehicle in
            var copy = vehicle
            if vehicle.id == leading.id {
                copy.yourBid = vehicle.currentBid
            } else if vehicle.id == outbid?.id {
                copy.yourBid = outbidAmount(for: vehicle)
            }
            return copy
        }
    }

    /// Whether a lot can carry a seeded position: has bids and can still take another one.
    private static func isEligible(_ vehicle: VehicleModel, now: Date) -> Bool {
        guard vehicle.bidCount > 0, vehicle.currentBid != nil else { return false }
        return BiddingRules.canTakeAnotherBid(vehicle, at: now)
    }

    /// The seeded "outbid" amount: one step below the current bid, floored at the starting bid.
    ///
    /// - Returns: `nil` when no amount strictly below the current bid reaches the starting bid
    ///   (e.g. current bid equals the starting bid), since that bid would be winning, not outbid.
    private static func outbidAmount(for vehicle: VehicleModel) -> Int? {
        guard let currentBid = vehicle.currentBid else { return nil }
        let step = BiddingRules.step(currentBid: currentBid, bidCount: vehicle.bidCount)
        let amount = max(vehicle.startingBid, currentBid - step)
        return amount < currentBid ? amount : nil
    }

}
