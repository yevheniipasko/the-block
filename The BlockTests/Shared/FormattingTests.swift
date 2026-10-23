//
//  FormattingTests.swift
//  The Block
//
//  Tests for the shared formatters (CAD money, kilometres, countdown) and the ending-soon
//  rule (TIME-3).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Shared display formatters and the ending-soon rule.
@MainActor
struct FormattingTests {

    private let now = TestDates.reference

    @Test("Money is whole CAD with grouping")
    func currency() {
        #expect(Formatting.currency(24_500) == "$24,500")
    }

    @Test("Odometer is grouped kilometres")
    func kilometres() {
        #expect(Formatting.kilometres(47_731) == "47,731 km")
    }

    @Test(
        "TIME-3: countdown switches units at one day and one hour",
        arguments: [
            (TimeInterval(2 * 86_400 + 4 * 3_600 + 59), "2d 4h"),
            (TimeInterval(86_400), "1d 0h"),
            (TimeInterval(4 * 3_600 + 12 * 60), "4h 12m"),
            (TimeInterval(3_600), "1h 0m"),
            (TimeInterval(12 * 60 + 5), "12m 05s"),
            (TimeInterval(-30), "0m 00s")
        ]
    )
    func countdown(remaining: TimeInterval, expected: String) {
        #expect(Formatting.countdown(from: now, to: now.addingTimeInterval(remaining)) == expected)
    }

    @Test("TIME-3: active auctions under an hour are ending soon")
    func endingSoon() {
        #expect(AuctionStatus.active(endsAt: now.addingTimeInterval(59 * 60)).isEndingSoon(now: now))
        #expect(!AuctionStatus.active(endsAt: now.addingTimeInterval(61 * 60)).isEndingSoon(now: now))
        #expect(!AuctionStatus.upcoming(startsAt: now.addingTimeInterval(60)).isEndingSoon(now: now))
    }

}
