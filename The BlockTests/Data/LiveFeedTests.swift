//
//  LiveFeedTests.swift
//  The Block
//
//  Tests for the simulated live feed and repository streams: snapshot, competing bids,
//  per-lot and inventory updates, reconnect, broadcaster cleanup (LIVE-1, LIVE-2, DATA-3).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Simulated server feed and the repository streams built on it: snapshot, competing bids,
/// per-lot and inventory updates, reconnect, and subscriber cleanup.
@MainActor
struct LiveFeedTests {

    private let launch = TestDates.reference
    private var clock: FixedClock { FixedClock(now: launch) }

    /// Starts at launch (the only lot is the anchor) → active, with bids and a high Buy Now.
    private func activeLot(id: UUID = UUID(), currentBid: Int = 20_000, bidCount: Int = 5) -> VehicleModel {
        .fixture(id: id, auctionStart: Date(timeIntervalSince1970: 0), buyNowPrice: 90_000,
                 currentBid: currentBid, bidCount: bidCount)
    }

    /// Stub server plus a repository on it that has already loaded `vehicles`.
    private func makeStack(_ vehicles: [VehicleModel]) async -> (SimulatedAuctionDataSource, VehicleRepository) {
        let server = SimulatedAuctionDataSource.stub(result: .success(vehicles), clock: clock)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        await repository.load()
        return (server, repository)
    }

    @Test("LIVE-1: the feed opens with a normalized snapshot")
    func feedStartsWithSnapshot() async throws {
        let server = SimulatedAuctionDataSource.stub(result: .success([activeLot()]), clock: clock)
        var iterator = server.vehicleFeed().makeAsyncIterator()

        guard case .snapshot(let vehicles) = try await iterator.next() else {
            Issue.record("Expected a snapshot first")
            return
        }
        #expect(vehicles.first?.auctionStart == launch)
    }

    @Test("LIVE-2: a competing bid raises an active lot by its minimum step and outbids you")
    func competingBidOutbidsYou() async throws {
        let id = UUID()
        let (server, repository) = await makeStack([activeLot(id: id)])
        _ = try await repository.placeBid(20_500, on: id).get()
        #expect(repository.vehicle(id: id)?.isYouHighBidder == true)
        var updates = repository.vehicleUpdates(id: id).makeAsyncIterator()
        _ = await updates.next()

        let competing = try #require(server.simulateCompetingBid())
        _ = await updates.next()

        #expect(competing.currentBid == 21_000)
        #expect(competing.isYouOutbid)
        let cached = try #require(repository.vehicle(id: id))
        #expect(cached.currentBid == 21_000)
        #expect(cached.bidCount == 7)
        #expect(cached.isYouOutbid)
    }

    @Test("LIVE-2: no competing bid lands on ended lots or at the Buy Now ceiling")
    func competingBidSkipsIneligibleLots() async {
        // With fewer than 121 lots the latest start is "now", so the anchor is active and the other has ended.
        let anchorStart = Date(timeIntervalSince1970: 1_000_000)
        let atCeiling = VehicleModel.fixture(auctionStart: anchorStart, buyNowPrice: 20_500,
                                             currentBid: 20_000, bidCount: 5)
        let ended = VehicleModel.fixture(auctionStart: anchorStart.addingTimeInterval(-TestDates.hours(73)))
        let (server, _) = await makeStack([atCeiling, ended])

        #expect(server.simulateCompetingBid() == nil)
    }

    @Test("LIVE-1: vehicleUpdates yields the current copy, then every change to that lot")
    func vehicleUpdatesStream() async throws {
        let id = UUID()
        let (server, repository) = await makeStack([activeLot(id: id)])
        var updates = repository.vehicleUpdates(id: id).makeAsyncIterator()

        let first = await updates.next()
        #expect(first?.currentBid == 20_000)

        await repository.placeBid(20_500, on: id)
        let afterYourBid = await updates.next()
        #expect(afterYourBid?.currentBid == 20_500)

        // The only lot is active, so the market must bid on it.
        server.simulateCompetingBid()
        let afterMarket = await updates.next()
        #expect(afterMarket?.isYouOutbid == true)
    }

    @Test("LIVE-1: a subscriber that starts before the first load receives the snapshot copy")
    func vehicleUpdatesBeforeLoad() async {
        let id = UUID()
        let server = SimulatedAuctionDataSource.stub(result: .success([activeLot(id: id)]), clock: clock)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        var updates = repository.vehicleUpdates(id: id).makeAsyncIterator()

        await repository.load()

        #expect(await updates.next()?.id == id)
    }

    @Test("LIVE-1: a subscriber that starts before loading receives every lot of a large snapshot")
    func largeSnapshotIsNotTruncated() async {
        let lots = (0..<150).map { _ in activeLot() }
        let server = SimulatedAuctionDataSource.stub(result: .success(lots), clock: clock)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        var updates = repository.inventoryUpdates().makeAsyncIterator()

        await repository.load()

        var received = Set<VehicleModel.ID>()
        for _ in lots {
            if let vehicle = await updates.next() {
                received.insert(vehicle.id)
            }
        }
        #expect(received == Set(lots.map(\.id)))
    }

    @Test("LIVE-1: inventoryUpdates reports lots changed by anyone")
    func inventoryUpdatesStream() async {
        let id = UUID()
        let (_, repository) = await makeStack([activeLot(id: id)])
        var updates = repository.inventoryUpdates().makeAsyncIterator()

        await repository.placeBid(20_500, on: id)

        #expect(await updates.next()?.id == id)
    }

    @Test("DATA-3 / LIVE-1: a failed connection can be retried")
    func reconnectAfterFailure() async {
        let attempts = AttemptCounter()
        let lot = activeLot()
        let server = SimulatedAuctionDataSource(
            loadSnapshot: {
                attempts.count += 1
                if attempts.count == 1 { throw StubError() }
                return [lot]
            },
            clock: clock,
            latency: .zero,
            market: nil,
            generator: SeededGenerator(seed: 1)
        )
        let repository = VehicleRepository(dataSource: server, clock: clock)

        await repository.load()
        guard case .failed = repository.loadState else {
            Issue.record("Expected failed state, got \(repository.loadState)")
            return
        }

        await repository.load()
        #expect(repository.loadState == .loaded)
        #expect(repository.vehicles.count == 1)
    }

    @Test("DATA-3 / LIVE-1: reconnecting a live feed never reports the replaced connection as failed")
    func reloadWhileLiveNeverFails() async {
        let (_, repository) = await makeStack([activeLot()])
        var states: [LoadState] = []
        let recorder = Task {
            for await state in repository.loadStateUpdates() {
                states.append(state)
            }
        }
        await Task.yield()

        await repository.load()
        await repository.load()
        for _ in 0..<20 {
            await Task.yield()
        }
        recorder.cancel()

        #expect(repository.loadState == .loaded)
        #expect(!states.contains { if case .failed = $0 { true } else { false } })
    }

    @Test("LIVE-1: a cancelled subscriber is removed from the broadcaster")
    func cancelledSubscriberIsRemoved() async {
        let broadcaster = StreamBroadcaster<Int>()
        let task = Task {
            for await _ in broadcaster.stream() {}
        }
        await Task.yield()
        #expect(broadcaster.subscriberCount == 1)

        task.cancel()
        await task.value
        for _ in 0..<5 where broadcaster.subscriberCount > 0 {
            await Task.yield()
        }

        #expect(broadcaster.subscriberCount == 0)
    }

}

/// Counts snapshot load attempts so the first one can fail and the retry succeed.
@MainActor
private final class AttemptCounter {
    var count = 0
}
