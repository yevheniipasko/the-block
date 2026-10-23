//
//  VehicleDataSourceTests.swift
//  The Block
//
//  Tests for decoding and mapping vehicles.json: nullable fields, timezone-less dates,
//  enum and image mapping, missing resource (DATA-1…DATA-3, DETAIL-1).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Decoding the bundled dataset and mapping DTOs to models, including mapping errors.
@MainActor
struct VehicleDataSourceTests {

    @Test("DATA-1: all 200 bundled vehicles decode with their nullable fields")
    func decodesBundledDataset() async throws {
        let vehicles = try BundledVehicleLoader().loadVehicles()

        #expect(vehicles.count == 200)
        #expect(vehicles.count { $0.reservePrice == nil } == 60)
        #expect(vehicles.count { $0.buyNowPrice == nil } == 161)
        #expect(vehicles.count { $0.currentBid == nil } == 112)
        #expect(vehicles.allSatisfy { $0.yourBid == nil && $0.yourPurchasePrice == nil })
    }

    @Test("DATA-2: auction_start without timezone decodes as the same wall-clock time in UTC")
    func decodesTimezoneLessDate() throws {
        let vehicles = try VehicleDecoder.decode(Self.json(auctionStart: "2026-04-05T14:00:00"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let components = utc.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: try #require(vehicles.first).auctionStart
        )
        #expect(components == DateComponents(year: 2026, month: 4, day: 5, hour: 14, minute: 0))
    }

    @Test("TIME-1: spacing across a DST change (Sydney, 2026-04-05 03:00) equals the wall-clock difference")
    func spacingIgnoresDeviceTimeZone() throws {
        let before = try #require(try VehicleDecoder.decode(Self.json(auctionStart: "2026-04-05T01:00:00")).first)
        let after = try #require(try VehicleDecoder.decode(Self.json(auctionStart: "2026-04-05T05:00:00")).first)

        #expect(after.auctionStart.timeIntervalSince(before.auctionStart) == TestDates.hours(4))
    }

    @Test("DETAIL-1: placeholder image URLs are rewritten to PNG so AsyncImage can render them")
    func placeholderImagesUsePNG() throws {
        let vehicle = try #require(try VehicleDecoder.decode(Self.json(auctionStart: "2026-04-05T14:00:00")).first)

        #expect(vehicle.images.first?.absoluteString == "https://placehold.co/800x600/png")
    }

    @Test("DATA-2: malformed auction_start throws a mapping error instead of crashing")
    func malformedDateThrows() {
        #expect(throws: VehicleMappingError.invalidField(name: "auction_start", value: "April 5th", lot: "A-0043")) {
            try VehicleDecoder.decode(Self.json(auctionStart: "April 5th"))
        }
    }

    @Test("DATA-2: unknown enum values throw a mapping error naming the field")
    func unknownEnumThrows() {
        let data = Data(String(decoding: Self.json(auctionStart: "2026-04-05T14:00:00"), as: UTF8.self)
            .replacingOccurrences(of: "\"SUV\"", with: "\"minivan\"").utf8)

        #expect(throws: VehicleMappingError.invalidField(name: "body_style", value: "minivan", lot: "A-0043")) {
            try VehicleDecoder.decode(data)
        }
    }

    @Test("DATA-3: a missing resource throws resourceNotFound")
    func missingResourceThrows() async {
        let loader = BundledVehicleLoader(resourceName: "does-not-exist")

        #expect(throws: VehicleDataSourceError.resourceNotFound(name: "does-not-exist")) {
            try loader.loadVehicles()
        }
    }

    /// One-vehicle JSON payload in the bundled file's shape, with a configurable `auction_start`.
    private static func json(auctionStart: String) -> Data {
        Data("""
        [{
          "id": "3cc3b89e-68b0-479e-af39-bca6251ea0b4", "vin": "TRD7L1KS0HNB5X3K3",
          "year": 2023, "make": "Ford", "model": "Bronco", "trim": "Big Bend",
          "body_style": "SUV", "exterior_color": "Burgundy", "interior_color": "Beige",
          "engine": "2.7L EcoBoost V6", "transmission": "automatic", "drivetrain": "4WD",
          "odometer_km": 47731, "fuel_type": "gasoline", "condition_grade": 3.8,
          "condition_report": "Average condition.", "damage_notes": [],
          "title_status": "clean", "province": "Ontario", "city": "Toronto",
          "auction_start": "\(auctionStart)", "starting_bid": 14500,
          "reserve_price": null, "buy_now_price": null,
          "images": ["https://placehold.co/800x600"], "selling_dealership": "King City Auto",
          "lot": "A-0043", "current_bid": null, "bid_count": 0
        }]
        """.utf8)
    }

}
