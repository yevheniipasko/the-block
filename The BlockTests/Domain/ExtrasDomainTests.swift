import Foundation
import Testing
@testable import The_Block

@MainActor
struct BidPositionTests {

    private let now = TestDates.reference
    private var liveStart: Date { now.addingTimeInterval(-TestDates.hours(1)) }
    private var endedStart: Date { now.addingTimeInterval(-TestDates.hours(80)) }

    @Test("MYBIDS-2: no bid and no purchase means no position")
    func noPosition() {
        #expect(VehicleModel.fixture(auctionStart: liveStart).bidPosition(at: now) == nil)
    }

    @Test("MYBIDS-2: live lots are winning or outbid")
    func liveLots() {
        let winning = VehicleModel.fixture(auctionStart: liveStart, currentBid: 20_000, bidCount: 3, yourBid: 20_000)
        let outbid = VehicleModel.fixture(auctionStart: liveStart, currentBid: 21_000, bidCount: 4, yourBid: 20_000)

        #expect(winning.bidPosition(at: now) == .winning)
        #expect(outbid.bidPosition(at: now) == .outbid)
    }

    @Test("MYBIDS-2: ended lots are won or lost; Buy Now is bought")
    func endedLots() {
        let won = VehicleModel.fixture(auctionStart: endedStart, currentBid: 20_000, bidCount: 3, yourBid: 20_000)
        let lost = VehicleModel.fixture(auctionStart: endedStart, currentBid: 21_000, bidCount: 4, yourBid: 20_000)
        let belowFloor = VehicleModel.fixture(auctionStart: endedStart, reservePrice: 25_000,
                                              currentBid: 20_000, bidCount: 3, yourBid: 20_000)
        let bought = VehicleModel.fixture(auctionStart: liveStart, buyNowPrice: 30_000, yourPurchasePrice: 30_000)

        #expect(won.bidPosition(at: now) == .won)
        #expect(lost.bidPosition(at: now) == .lost)
        #expect(belowFloor.bidPosition(at: now) == .lost)
        #expect(bought.bidPosition(at: now) == .bought)
    }

}

@MainActor
struct FeeScheduleTests {

    @Test(
        "FEES-3: buyer fee tiers switch exactly at $10,000 and $30,000",
        arguments: [
            (9_999, 300), (10_000, 500), (29_999, 500), (30_000, 600), (31_025, 621), (45_000, 900)
        ]
    )
    func buyerFeeTiers(amount: Int, expected: Int) {
        #expect(FeeSchedule.buyerFee(for: amount) == expected)
    }

    @Test("FEES-1: total = amount + buyer fee + $99 documentation fee")
    func total() {
        let estimate = FeeSchedule.estimate(for: 24_000)

        #expect(estimate.buyerFee == 500)
        #expect(estimate.documentationFee == 99)
        #expect(estimate.total == 24_599)
    }

}

@MainActor
struct DemoSeedTests {

    private let now = TestDates.reference

    @Test("MYBIDS-7: the first two eligible lots become leading and outbid")
    func seedsTwoPositions() {
        let live = now.addingTimeInterval(-TestDates.hours(1))
        let noBids = VehicleModel.fixture(auctionStart: live).with(lot: "A-0001")
        let leading = VehicleModel.fixture(auctionStart: live, currentBid: 20_000, bidCount: 5).with(lot: "A-0002")
        let outbid = VehicleModel.fixture(auctionStart: live, currentBid: 15_000, bidCount: 2).with(lot: "A-0003")
        let untouched = VehicleModel.fixture(auctionStart: live, currentBid: 9_000, bidCount: 2).with(lot: "A-0004")

        let seeded = DemoSeed.apply(to: [untouched, outbid, noBids, leading], now: now)
        let byLot = Dictionary(uniqueKeysWithValues: seeded.map { ($0.lot, $0) })

        #expect(byLot["A-0002"]?.bidPosition(at: now) == .winning)
        #expect(byLot["A-0003"]?.bidPosition(at: now) == .outbid)
        #expect(byLot["A-0003"]?.yourBid == 14_750)
        #expect(byLot["A-0001"]?.yourBid == nil)
        #expect(byLot["A-0004"]?.yourBid == nil)
    }

    @Test("MYBIDS-7: lots that ended or sit at the Buy Now ceiling are skipped")
    func skipsIneligibleLots() {
        let ended = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(80)),
                                         currentBid: 20_000, bidCount: 5)
        let atCeiling = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(1)),
                                             buyNowPrice: 20_500, currentBid: 20_000, bidCount: 5)

        let seeded = DemoSeed.apply(to: [ended, atCeiling], now: now)

        #expect(seeded.allSatisfy { $0.yourBid == nil })
    }

}

private extension VehicleModel {
    /// Copy with a different lot number (the shared fixture always uses "A-0043").
    func with(lot: String) -> VehicleModel {
        VehicleModel(
            id: id, vin: vin, year: year, make: make, model: model, trim: trim, bodyStyle: bodyStyle,
            exteriorColor: exteriorColor, interiorColor: interiorColor, engine: engine,
            transmission: transmission, drivetrain: drivetrain, odometerKm: odometerKm, fuelType: fuelType,
            conditionGrade: conditionGrade, conditionReport: conditionReport, damageNotes: damageNotes,
            titleStatus: titleStatus, province: province, city: city, auctionStart: auctionStart,
            startingBid: startingBid, reservePrice: reservePrice, buyNowPrice: buyNowPrice, images: images,
            sellingDealership: sellingDealership, lot: lot, currentBid: currentBid, bidCount: bidCount,
            yourBid: yourBid, yourPurchasePrice: yourPurchasePrice
        )
    }
}
