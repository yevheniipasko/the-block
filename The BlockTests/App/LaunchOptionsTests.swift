//
//  LaunchOptionsTests.swift
//  The Block
//
//  Tests for parsing the -market launch argument and the simulated-market settings
//  each mode maps to (UX-4, LIVE-2).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Testing
@testable import The_Block

/// Parsing of the `-market` launch argument and the market settings each mode produces.
@MainActor
struct LaunchOptionsTests {

    @Test(
        "UX-4: -market switches the simulated market for UI tests",
        arguments: [
            (["app"], LaunchOptions.MarketMode.standard),
            (["app", "-market", "off"], .off),
            (["app", "-market", "fast"], .fast),
            (["app", "-market"], .standard),
            (["app", "-market", "turbo"], .standard)
        ]
    )
    func parsesMarketFlag(arguments: [String], expected: LaunchOptions.MarketMode) {
        #expect(LaunchOptions(arguments: arguments).market == expected)
    }

    @Test("LIVE-2: market off disables competing bids; fast always targets your lots")
    func marketSettings() {
        #expect(LaunchOptions(market: .off).marketSettings == nil)
        #expect(LaunchOptions(market: .fast).marketSettings?.targetsYourLotsProbability == 1)
        #expect(LaunchOptions.standard.marketSettings?.interval == .seconds(6))
    }

}
