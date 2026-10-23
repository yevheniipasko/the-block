//
//  BidLiveUpdatesTests.swift
//  The Block
//
//  Tests for an open bid / Buy Now sheet following the live feed: competing bids, lot ending,
//  Buy Now turning unavailable, connection failures (LIVE-3, LIVE-4, BID-7, BID-11).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// An open bid / Buy Now sheet following the live feed (spec LIVE-3, LIVE-4).
@MainActor
struct BidLiveUpdatesTests {

    /// Stub server plus a repository on it that has already loaded `vehicles`.
    private func makeStack(
        _ vehicles: [VehicleModel],
        clock: AuctionClockProtocol = FixedClock(now: TestDates.reference)
    ) async -> (SimulatedAuctionDataSource, VehicleRepository) {
        let server = SimulatedAuctionDataSource.stub(result: .success(vehicles), clock: clock)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        await repository.load()
        return (server, repository)
    }

    /// Lets queued main-actor work (feed → repository → view model) run until `condition` holds.
    ///
    /// Bounded, and every iteration yields, so the updates being waited for can be delivered.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<Constants.maxYields where !condition() {
            await Task.yield()
        }
    }

    /// Waits a few clock ticks so a moved clock reaches the view model.
    private func waitForClockTick() async {
        try? await Task.sleep(for: Constants.clockTick * 5)
    }

    // MARK: - LIVE-3: competing bids

    @Test("LIVE-3: a competing bid while editing raises the minimum and invalidates the typed amount")
    func competingBidWhileEditing() async throws {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (server, repository) = await makeStack([vehicle])
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)
        let observing = Task { await viewModel.observeVehicle() }
        #expect(viewModel.amountText == "24000")
        #expect(viewModel.canReview)

        try #require(server.simulateCompetingBid() != nil)
        await settle { viewModel.minimumBid == 25_000 }

        #expect(viewModel.minimumExplanation == "Minimum $25,000 · step $1,000 · Hot lot, 15 bids")
        #expect(viewModel.amountText == "24000")
        #expect(viewModel.validationRejection == .belowMinimum(minimum: 25_000))
        #expect(viewModel.validationMessage == "Bid at least $25,000.")
        #expect(!viewModel.canReview)
        observing.cancel()
        await observing.value
    }

    @Test("LIVE-3: a competing bid during review returns to editing with the below-minimum message")
    func competingBidDuringReview() async throws {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (server, repository) = await makeStack([vehicle])
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)
        let observing = Task { await viewModel.observeVehicle() }
        viewModel.review()
        #expect(viewModel.phase == .reviewing)

        try #require(server.simulateCompetingBid() != nil)
        await settle { viewModel.phase == .editing }

        #expect(viewModel.phase == .editing)
        #expect(viewModel.amount == 24_000)
        #expect(viewModel.validationMessage == "Bid at least $25,000.")
        observing.cancel()
        await observing.value
    }

    @Test("LIVE-3: being outbid while the sheet is open shows the outbid notice")
    func outbidNotice() async throws {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (server, repository) = await makeStack([vehicle])
        _ = try await repository.placeBid(24_000, on: vehicle.id).get()
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)
        let observing = Task { await viewModel.observeVehicle() }
        #expect(!viewModel.isOutbid)

        try #require(server.simulateCompetingBid() != nil)
        await settle { viewModel.isOutbid }

        #expect(viewModel.isOutbid)
        #expect(viewModel.minimumBid == 26_000)
        observing.cancel()
        await observing.value
    }

    // MARK: - LIVE-3 / BID-7: lot ends while open

    @Test("LIVE-3 / BID-7: a lot ending while the sheet is open shows the ended state")
    func lotEndsWhileOpen() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let clock = MutableClock(now: TestDates.reference)
        let (_, repository) = await makeStack([vehicle], clock: clock)
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository, clockTick: Constants.clockTick)
        let observing = Task { await viewModel.observeVehicle() }
        viewModel.review()
        #expect(!viewModel.isAuctionEnded)

        clock.now = TestDates.reference.addingTimeInterval(AuctionSchedule.duration)
        await waitForClockTick()
        await settle { viewModel.isAuctionEnded }

        #expect(viewModel.isAuctionEnded)
        #expect(viewModel.phase == .editing)
        #expect(!viewModel.canReview)
        observing.cancel()
        await observing.value
    }

    // MARK: - BID-11: Buy Now becomes unavailable while open

    @Test("BID-11 / LIVE-3: Buy Now turns unavailable when the lot is bought while the sheet is open")
    func buyNowUnavailableAfterPurchase() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 31_000)
        let (_, repository) = await makeStack([vehicle])
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)
        let observing = Task { await viewModel.observeVehicle() }
        #expect(viewModel.buyNowUnavailableReason == nil)

        // Bought from another screen; this sheet only learns about it from the feed.
        await repository.buyNow(vehicle.id)
        await settle { viewModel.buyNowUnavailableReason != nil }

        #expect(viewModel.buyNowUnavailableReason == "You bought this lot.")
        #expect(viewModel.phase == .editing)
        observing.cancel()
        await observing.value
    }

    @Test("BID-11 / LIVE-3: Buy Now turns unavailable when the lot ends while the sheet is open")
    func buyNowUnavailableAfterEnding() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 31_000)
        let clock = MutableClock(now: TestDates.reference)
        let (_, repository) = await makeStack([vehicle], clock: clock)
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository, clockTick: Constants.clockTick)
        let observing = Task { await viewModel.observeVehicle() }
        #expect(viewModel.buyNowUnavailableReason == nil)

        clock.now = TestDates.reference.addingTimeInterval(AuctionSchedule.duration)
        await waitForClockTick()
        await settle { viewModel.buyNowUnavailableReason != nil }

        #expect(viewModel.buyNowUnavailableReason == "This auction has ended.")
        observing.cancel()
        await observing.value
    }

    // MARK: - LIVE-4: connection failures

    @Test("LIVE-4: a bid that can't reach the server shows the reason and keeps the sheet open")
    func bidConnectionFailed() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let repository = VehicleRepository(
            dataSource: UnreachableDataSource(vehicles: [vehicle]),
            clock: FixedClock(now: TestDates.reference)
        )
        await repository.load()
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)

        viewModel.review()
        await viewModel.submitBid()

        #expect(viewModel.phase == .editing)
        #expect(viewModel.rejectionMessage == Constants.connectionFailedMessage)
        #expect(viewModel.amount == 24_000)
        #expect(repository.vehicle(id: vehicle.id)?.bidCount == 14)
    }

    @Test("LIVE-4: a Buy Now that can't reach the server shows the reason and keeps the sheet open")
    func buyNowConnectionFailed() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 31_000)
        let repository = VehicleRepository(
            dataSource: UnreachableDataSource(vehicles: [vehicle]),
            clock: FixedClock(now: TestDates.reference)
        )
        await repository.load()
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)

        await viewModel.buyNow()

        #expect(viewModel.phase == .editing)
        #expect(viewModel.rejectionMessage == Constants.connectionFailedMessage)
        #expect(viewModel.buyNowUnavailableReason == nil)
        #expect(repository.vehicle(id: vehicle.id)?.isPurchasedByYou == false)
    }

}

/// Server whose feed works but whose bid / Buy Now requests never arrive.
private struct UnreachableDataSource: VehicleDataSourceProtocol {

    let vehicles: [VehicleModel]

    /// Yields one snapshot of `vehicles` and stays open.
    func vehicleFeed() -> AsyncThrowingStream<VehicleFeedEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<VehicleFeedEvent, Error>.makeStream()
        continuation.yield(.snapshot(vehicles))
        return stream
    }

    /// Always fails as if the device were offline.
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async throws -> VehicleModel {
        throw URLError(.notConnectedToInternet)
    }

    /// Always fails as if the device were offline.
    func buyNow(_ id: VehicleModel.ID) async throws -> VehicleModel {
        throw URLError(.notConnectedToInternet)
    }

}

/// Wait budgets, the fast clock tick, and the expected connection-failure message.
private enum Constants {
    static let maxYields = 200
    static let clockTick: Duration = .milliseconds(10)
    static let connectionFailedMessage = "Not placed. Couldn't reach the auction. Check your connection and try again."
}
