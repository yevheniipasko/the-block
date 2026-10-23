//
//  InventoryQueryTests.swift
//  The Block
//
//  Tests for InventoryQuery search, filters, and sorting, and for cursor-based Paginator
//  paging (LIST-2…LIST-4, LIST-7).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Search, filters, and sort orders applied by `InventoryQuery`.
@MainActor
struct InventoryQueryTests {

    private let now = TestDates.reference

    @Test("LIST-2: search is case-insensitive across make, model, lot, VIN, dealership; all terms must match")
    func search() {
        let vehicles = [VehicleModel.fixture(), VehicleModel.fixture()]
        var query = InventoryQuery()

        query.searchText = "ford bronco"
        #expect(query.apply(to: vehicles, now: now).count == 2)
        query.searchText = "a-0043 king city"
        #expect(query.apply(to: vehicles, now: now).count == 2)
        query.searchText = "ford mustang"
        #expect(query.apply(to: vehicles, now: now).isEmpty)
    }

    @Test("LIST-3: status filter uses the auction state at query time")
    func statusFilter() {
        let live = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(1)))
        let upcoming = VehicleModel.fixture(auctionStart: now.addingTimeInterval(TestDates.hours(1)))
        var query = InventoryQuery()
        query.statuses = [.upcoming]

        #expect(query.apply(to: [live, upcoming], now: now).map(\.id) == [upcoming.id])
    }

    @Test("LIST-3: Buy Now toggle keeps only priced lots")
    func buyNowFilter() {
        let priced = VehicleModel.fixture(buyNowPrice: 30_000)
        var query = InventoryQuery()
        query.buyNowOnly = true

        #expect(query.apply(to: [priced, .fixture()], now: now).map(\.id) == [priced.id])
    }

    @Test("LIST-4: ending soonest puts active by end time, then upcoming, then ended")
    func endingSoonest() {
        let endsLater = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(1)))
        let endsSooner = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(70)))
        let upcoming = VehicleModel.fixture(auctionStart: now.addingTimeInterval(TestDates.hours(1)))
        let ended = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(100)))

        let sorted = InventoryQuery().apply(to: [ended, upcoming, endsLater, endsSooner], now: now)

        #expect(sorted.map(\.id) == [endsSooner.id, endsLater.id, upcoming.id, ended.id])
    }

    @Test("LIST-4: price sort uses the current bid, falling back to the starting bid")
    func priceSort() {
        let cheap = VehicleModel.fixture(startingBid: 5_000)
        let bidUp = VehicleModel.fixture(startingBid: 4_000, currentBid: 9_000, bidCount: 3)
        var query = InventoryQuery()
        query.sort = .priceLowToHigh

        #expect(query.apply(to: [bidUp, cheap], now: now).map(\.id) == [cheap.id, bidUp.id])
    }

}

/// Cursor-based paging over a result list.
@MainActor
struct PaginatorTests {

    private let vehicles = (0..<45).map { _ in VehicleModel.fixture() }

    @Test("LIST-7: cursor pages walk the results without gaps or repeats")
    func walksAllPages() throws {
        var cursor: PageCursor?
        var seen: [VehicleModel.ID] = []
        repeat {
            let page = try Paginator.page(of: vehicles, after: cursor, limit: 20)
            #expect(page.totalCount == 45)
            seen += page.vehicles.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil

        #expect(seen == vehicles.map(\.id))
    }

    @Test("LIST-7: the last page has no next cursor")
    func lastPage() throws {
        let page = try Paginator.page(of: Array(vehicles.prefix(20)), after: nil, limit: 20)

        #expect(page.vehicles.count == 20)
        #expect(page.nextCursor == nil)
    }

    @Test("LIST-7: a cursor whose vehicle dropped out of the results is stale")
    func staleCursor() {
        #expect(throws: PagingError.staleCursor) {
            try Paginator.page(of: vehicles, after: PageCursor(afterID: UUID()), limit: 20)
        }
    }

}
