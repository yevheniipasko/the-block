//
//  MyBidsViewModelTests.swift
//  The Block
//
//  Tests for MyBidsViewModel grouping, live regrouping, outbid badge, and empty state
//  (MYBIDS-2, MYBIDS-4…MYBIDS-7).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Clock the test can move forward, so an auction can end while the screen is open.
@MainActor
private final class MovableClock: AuctionClockProtocol {
    var now: Date

    /// Starts the clock at `now`.
    init(now: Date) {
        self.now = now
    }
}

/// My bids ViewModel: grouping by position, live regrouping, outbid badge, and empty state.
@MainActor
struct MyBidsViewModelTests {

    /// Latest dataset start; normalization maps it to launch, so lots starting here are live for 72 h.
    private let anchorStart = Date(timeIntervalSince1970: 1_000_000)
    private let clock = FixedClock(now: TestDates.reference)

    // MARK: - Lots

    /// Live lot where the buyer holds the high bid.
    private func winning(lot: String = "W-1") -> VehicleModel {
        withLot(
            .fixture(auctionStart: anchorStart, buyNowPrice: 90_000, currentBid: 20_000, bidCount: 3, yourBid: 20_000),
            lot
        )
    }

    /// Live lot where someone else outbid the buyer.
    private func outbid(lot: String = "O-1") -> VehicleModel {
        withLot(
            .fixture(auctionStart: anchorStart, buyNowPrice: 90_000, currentBid: 21_000, bidCount: 4, yourBid: 20_000),
            lot
        )
    }

    /// Ended lot the buyer won with the high bid (no floor).
    private func won() -> VehicleModel {
        withLot(.fixture(auctionStart: endedStart, currentBid: 15_000, bidCount: 2, yourBid: 15_000), "N-1")
    }

    /// Lot the buyer bought with Buy Now.
    private func bought() -> VehicleModel {
        withLot(.fixture(auctionStart: anchorStart, buyNowPrice: 30_000, yourPurchasePrice: 30_000), "B-1")
    }

    /// Ended lot where someone else held the high bid.
    private func lost() -> VehicleModel {
        withLot(.fixture(auctionStart: endedStart, currentBid: 16_000, bidCount: 5, yourBid: 15_500), "L-1")
    }

    /// Live lot with bids but none from the buyer.
    private func untouched() -> VehicleModel {
        withLot(.fixture(auctionStart: anchorStart, currentBid: 12_000, bidCount: 1), "U-1")
    }

    /// Start 73 h before the anchor, so the auction has ended at launch.
    private var endedStart: Date {
        anchorStart.addingTimeInterval(-TestDates.hours(73))
    }

    /// Copy of `vehicle` with a different lot number.
    private func withLot(_ vehicle: VehicleModel, _ lot: String) -> VehicleModel {
        VehicleModel(
            id: vehicle.id, vin: vehicle.vin, year: vehicle.year, make: vehicle.make, model: vehicle.model,
            trim: vehicle.trim, bodyStyle: vehicle.bodyStyle, exteriorColor: vehicle.exteriorColor,
            interiorColor: vehicle.interiorColor, engine: vehicle.engine, transmission: vehicle.transmission,
            drivetrain: vehicle.drivetrain, odometerKm: vehicle.odometerKm, fuelType: vehicle.fuelType,
            conditionGrade: vehicle.conditionGrade, conditionReport: vehicle.conditionReport,
            damageNotes: vehicle.damageNotes, titleStatus: vehicle.titleStatus, province: vehicle.province,
            city: vehicle.city, auctionStart: vehicle.auctionStart, startingBid: vehicle.startingBid,
            reservePrice: vehicle.reservePrice, buyNowPrice: vehicle.buyNowPrice, images: vehicle.images,
            sellingDealership: vehicle.sellingDealership, lot: lot, currentBid: vehicle.currentBid,
            bidCount: vehicle.bidCount, yourBid: vehicle.yourBid, yourPurchasePrice: vehicle.yourPurchasePrice
        )
    }

    // MARK: - Grouping

    @Test("MYBIDS-2: lots are grouped Winning, Outbid, Won, Bought, Lost; lots without a position are left out")
    func groupsInOrder() async {
        let (_, repository) = await makeInventoryStack(
            [lost(), bought(), untouched(), won(), outbid(), winning()],
            clock: clock
        )

        let viewModel = MyBidsViewModel(repository: repository)

        #expect(viewModel.groups.map(\.position) == [.winning, .outbid, .won, .bought, .lost])
        #expect(viewModel.groups.map { $0.vehicles.map(\.lot) } == [["W-1"], ["O-1"], ["N-1"], ["B-1"], ["L-1"]])
        #expect(!viewModel.isEmpty)
    }

    @Test("MYBIDS-2: empty groups are hidden")
    func emptyGroupsHidden() async {
        let (_, repository) = await makeInventoryStack([lost(), winning(), untouched()], clock: clock)

        let viewModel = MyBidsViewModel(repository: repository)

        #expect(viewModel.groups.map(\.position) == [.winning, .lost])
    }

    // MARK: - Live updates

    @Test("MYBIDS-4: a competing bid moves the lot from Winning to Outbid without reopening the screen")
    func competingBidRegroups() async throws {
        let (server, repository) = await makeInventoryStack([winning()], clock: clock)
        let viewModel = MyBidsViewModel(repository: repository)
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await Task.yield()
        #expect(viewModel.groups.map(\.position) == [.winning])

        try #require(server.simulateCompetingBid() != nil)
        await waitUntil { viewModel.groups.map(\.position) == [.outbid] }

        #expect(viewModel.groups.map(\.position) == [.outbid])
        #expect(viewModel.outbidCount == 1)
    }

    @Test("MYBIDS-4: a new bid adds the lot to Winning")
    func newBidAppears() async throws {
        let target = untouched()
        let (_, repository) = await makeInventoryStack([target], clock: clock)
        let viewModel = MyBidsViewModel(repository: repository)
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await Task.yield()
        #expect(viewModel.isEmpty)

        _ = try await repository.placeBid(12_500, on: target.id).get()
        await waitUntil { !viewModel.isEmpty }

        #expect(viewModel.groups.map(\.position) == [.winning])
    }

    @Test("MYBIDS-4 / MYBIDS-7: a position in a snapshot larger than the update buffer is not lost")
    func largeSnapshotBurst() async {
        let others = (0..<100).map { _ in untouched() }
        let server = SimulatedAuctionDataSource.stub(result: .success([winning()] + others), clock: clock)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        let viewModel = MyBidsViewModel(repository: repository)
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        await Task.yield()
        #expect(viewModel.isEmpty)

        await repository.load()
        await waitUntil { !viewModel.isEmpty }

        #expect(viewModel.groups.map(\.position) == [.winning])
    }

    @Test("MYBIDS-4: when the auction ends, Winning becomes Won and Outbid becomes Lost")
    func auctionEndRegroups() async {
        let movable = MovableClock(now: TestDates.reference)
        let (_, repository) = await makeInventoryStack([winning(), outbid()], clock: movable)
        let viewModel = MyBidsViewModel(repository: repository)
        #expect(viewModel.groups.map(\.position) == [.winning, .outbid])

        movable.now = TestDates.reference.addingTimeInterval(TestDates.hours(73))
        viewModel.refreshPositions()

        #expect(viewModel.groups.map(\.position) == [.won, .lost])
    }

    // MARK: - Badge and empty state

    @Test("MYBIDS-6: outbidCount counts running lots where someone else leads")
    func outbidCount() async {
        let (_, repository) = await makeInventoryStack(
            [outbid(lot: "O-1"), outbid(lot: "O-2"), winning(), lost()],
            clock: clock
        )

        let viewModel = MyBidsViewModel(repository: repository)

        #expect(viewModel.outbidCount == 2)
        #expect(viewModel.groups.first { $0.position == .outbid }?.vehicles.map(\.lot) == ["O-1", "O-2"])
    }

    @Test("MYBIDS-5 / MYBIDS-6: no bids yet → empty, no outbid badge")
    func emptyState() async {
        let (_, repository) = await makeInventoryStack([untouched()], clock: clock)

        let viewModel = MyBidsViewModel(repository: repository)

        #expect(viewModel.isEmpty)
        #expect(viewModel.groups.isEmpty)
        #expect(viewModel.outbidCount == 0)
    }

}
