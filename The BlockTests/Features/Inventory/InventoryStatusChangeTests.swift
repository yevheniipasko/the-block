//
//  InventoryStatusChangeTests.swift
//  The Block
//
//  Tests that a status filter is re-applied when a lot starts or ends while the inventory is
//  shown, with no feed event (LIST-3, TIME-4).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Clock the test moves forward to let an auction end.
@MainActor
private final class SteppingClock: AuctionClockProtocol {
    var now: Date
    /// Starts the clock at `now`.
    init(now: Date) { self.now = now }
}

/// Status filters follow the clock (spec LIST-3, TIME-4).
@MainActor
struct InventoryStatusChangeTests {

    private let observers = InventoryObservers()

    @Test("LIST-3 / TIME-4: a lot that ends while a Live filter is on leaves the results and the count")
    func liveFilterDropsEndedLot() async {
        let clock = SteppingClock(now: TestDates.reference)
        // The later start is the anchor (starts at launch); the other ends one minute after launch.
        let anchor = VehicleModel.fixture(auctionStart: Date(timeIntervalSince1970: TestDates.hours(72)))
        let endingSoon = VehicleModel.fixture(auctionStart: Date(timeIntervalSince1970: 60))
        let repository = await makeInventoryStack([anchor, endingSoon], clock: clock).repository
        let viewModel = InventoryViewModel(repository: repository, clockTick: .milliseconds(10))
        observers.start(viewModel)
        let ticker = Task { await viewModel.observeStatusChanges() }
        defer { ticker.cancel() }
        await waitUntil { viewModel.isInventoryLoaded }
        viewModel.setFilter(.status(.active), isOn: true)
        await settle(viewModel)
        #expect(viewModel.totalCount == 2)

        clock.now = TestDates.reference.addingTimeInterval(120)
        for _ in 0..<100 where viewModel.totalCount != 1 {
            try? await Task.sleep(for: .milliseconds(10))
            await settle(viewModel)
        }

        #expect(viewModel.totalCount == 1)
        #expect(viewModel.loadedIDs == [anchor.id])
    }

    @Test("LIST-3: without a status filter, time passing doesn't reload the page")
    func noStatusFilterNoRestart() async {
        let clock = SteppingClock(now: TestDates.reference)
        let anchor = VehicleModel.fixture(auctionStart: Date(timeIntervalSince1970: TestDates.hours(72)))
        let endingSoon = VehicleModel.fixture(auctionStart: Date(timeIntervalSince1970: 60))
        let repository = await makeInventoryStack([anchor, endingSoon], clock: clock).repository
        let viewModel = InventoryViewModel(repository: repository, clockTick: .milliseconds(10))
        observers.start(viewModel)
        let ticker = Task { await viewModel.observeStatusChanges() }
        defer { ticker.cancel() }
        await waitUntil { viewModel.isInventoryLoaded }
        await settle(viewModel)
        let firstTask = viewModel.loadTask

        clock.now = TestDates.reference.addingTimeInterval(120)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.totalCount == 2)
        #expect(viewModel.loadTask == firstTask)
    }

}
