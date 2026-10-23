//
//  LaunchOptions.swift
//  The Block
//
//  Launch-time switches parsed from process arguments (`-market off|fast`),
//  used by UI tests to control the simulated market.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation

/// Launch-time switches, mainly for UI tests (spec UX-4, LIVE-2).
///
/// Pass `-market off` for deterministic UI tests (no competing bids) or `-market fast` to make
/// the simulated market outbid you within seconds. A normal launch uses `.standard`.
struct LaunchOptions: Equatable, Sendable {

    /// How the simulated market behaves for this launch; the raw value is the `-market` argument.
    enum MarketMode: String, Sendable {
        /// A competing bid every ~6 s (spec LIVE-2).
        case standard
        /// No competing bids, for deterministic UI tests.
        case off
        /// A competing bid every second, always on a lot you're winning when there is one.
        case fast
    }

    /// Options for a normal launch.
    static let standard = LaunchOptions(market: .standard)

    let market: MarketMode

    init(market: MarketMode) {
        self.market = market
    }

    /// Reads `-market <mode>` from process arguments; anything missing or unknown means `.standard`.
    init(arguments: [String]) {
        guard let flagIndex = arguments.firstIndex(of: Constants.marketFlag),
              arguments.indices.contains(flagIndex + 1),
              let mode = MarketMode(rawValue: arguments[flagIndex + 1]) else {
            self.init(market: .standard)
            return
        }
        self.init(market: mode)
    }

    /// Simulated-market settings for this launch, or `nil` when the market is off.
    var marketSettings: SimulatedAuctionDataSource.Market? {
        switch market {
        case .standard:
            SimulatedAuctionDataSource.Market(
                interval: Constants.standardInterval,
                targetsYourLotsProbability: Constants.standardTargetsYourLots
            )
        case .fast:
            SimulatedAuctionDataSource.Market(interval: Constants.fastInterval, targetsYourLotsProbability: 1)
        case .off:
            nil
        }
    }

}

private enum Constants {
    static let marketFlag = "-market"
    /// Pause between simulated competing bids from other buyers (spec LIVE-2).
    static let standardInterval: Duration = .seconds(6)
    /// Chance a competing bid lands on a lot you're winning, so being outbid is visible in a demo.
    static let standardTargetsYourLots = 0.4
    static let fastInterval: Duration = .seconds(1)
}
