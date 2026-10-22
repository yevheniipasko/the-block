import Foundation
@testable import The_Block

/// Clock pinned to a fixed moment so time-based rules are deterministic.
@MainActor
struct FixedClock: AuctionClockProtocol {
    var now: Date
}

/// Data source returning canned vehicles, or failing on demand.
@MainActor
struct StubVehicleDataSource: VehicleDataSourceProtocol {
    var result: Result<[VehicleModel], Error>

    func loadVehicles() async throws -> [VehicleModel] {
        try result.get()
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
