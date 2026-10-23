//
//  TestFixtures.swift
//  The Block
//
//  Shared test fixtures: fixed clock, stub data source and repository, seeded RNG,
//  reference dates, and the VehicleModel fixture.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
@testable import The_Block

/// Clock pinned to a fixed moment so time-based rules are deterministic.
@MainActor
struct FixedClock: AuctionClockProtocol {
    var now: Date
}

@MainActor
extension SimulatedAuctionDataSource {
    /// Fake server serving canned vehicles (or failing), with no market and optional latency.
    static func stub(
        result: Result<[VehicleModel], Error>,
        clock: AuctionClockProtocol,
        latency: Duration = .zero
    ) -> SimulatedAuctionDataSource {
        SimulatedAuctionDataSource(
            loadSnapshot: { try result.get() },
            clock: clock,
            latency: latency,
            market: nil,
            generator: SeededGenerator(seed: 42)
        )
    }
}

@MainActor
extension VehicleRepository {
    /// Repository on a stub server sharing one clock, so normalization and rules agree on "now".
    static func stubbed(
        result: Result<[VehicleModel], Error>,
        clock: AuctionClockProtocol,
        actionLatency: Duration = .zero
    ) -> VehicleRepository {
        VehicleRepository(
            dataSource: SimulatedAuctionDataSource.stub(result: result, clock: clock, latency: actionLatency),
            clock: clock
        )
    }
}

/// Deterministic generator (SplitMix64) so simulated-market tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

struct StubError: Error {}

enum TestDates {
    /// 2026-04-03 12:00:00 UTC — an arbitrary, fixed reference point.
    static let reference = Date(timeIntervalSince1970: 1_775_217_600)

    static func hours(_ value: Double) -> TimeInterval { value * 60 * 60 }
}

@MainActor
extension VehicleModel {

    static func fixture(
        id: UUID = UUID(),
        auctionStart: Date = TestDates.reference,
        startingBid: Int = 10_000,
        reservePrice: Int? = nil,
        buyNowPrice: Int? = nil,
        currentBid: Int? = nil,
        bidCount: Int = 0,
        yourBid: Int? = nil,
        yourPurchasePrice: Int? = nil
    ) -> VehicleModel {
        VehicleModel(
            id: id,
            vin: "TESTVIN0000000000",
            year: 2023,
            make: "Ford",
            model: "Bronco",
            trim: "Big Bend",
            bodyStyle: .suv,
            exteriorColor: "Burgundy",
            interiorColor: "Beige",
            engine: "2.7L EcoBoost V6",
            transmission: .automatic,
            drivetrain: .fourWheel,
            odometerKm: 47_731,
            fuelType: .gasoline,
            conditionGrade: 3.8,
            conditionReport: "Average condition.",
            damageNotes: [],
            titleStatus: .clean,
            province: "Ontario",
            city: "Toronto",
            auctionStart: auctionStart,
            startingBid: startingBid,
            reservePrice: reservePrice,
            buyNowPrice: buyNowPrice,
            images: [],
            sellingDealership: "King City Auto",
            lot: "A-0043",
            currentBid: currentBid,
            bidCount: bidCount,
            yourBid: yourBid,
            yourPurchasePrice: yourPurchasePrice
        )
    }

}
