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

    private let now = TestDates.reference
    private let vehicles = (0..<45).map { _ in VehicleModel.fixture() }

    /// `vehicles` as `query` orders them at `now`.
    private func page(
        _ vehicles: [VehicleModel],
        _ query: InventoryQuery,
        after cursor: PageCursor?,
        limit: Int = 20
    ) throws -> InventoryPage {
        let results = query.apply(to: vehicles, now: now)
        return try Paginator.page(of: results, after: cursor, limit: limit) { query.position(of: $0, now: now) }
    }

    @Test("LIST-7: cursor pages walk the results without gaps or repeats")
    func walksAllPages() throws {
        let query = InventoryQuery()
        var cursor: PageCursor?
        var seen: [VehicleModel.ID] = []
        repeat {
            let page = try page(vehicles, query, after: cursor)
            #expect(page.totalCount == 45)
            seen += page.vehicles.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil

        #expect(seen == query.apply(to: vehicles, now: now).map(\.id))
    }

    @Test("LIST-7: the last page has no next cursor")
    func lastPage() throws {
        let page = try page(Array(vehicles.prefix(20)), InventoryQuery(), after: nil)

        #expect(page.vehicles.count == 20)
        #expect(page.nextCursor == nil)
    }

    @Test("LIST-7: a cursor whose vehicle dropped out of the results is stale")
    func staleCursor() throws {
        let first = try page(vehicles, InventoryQuery(), after: nil)
        let others = Array(vehicles.filter { $0.id != first.vehicles.last?.id })

        #expect(throws: PagingError.staleCursor) {
            try page(others, InventoryQuery(), after: first.nextCursor)
        }
    }

    /// Five lots priced 1_000, 2_000, … 5_000.
    private var pricedLots: [VehicleModel] {
        (1...5).map { VehicleModel.fixture(startingBid: $0 * 1_000) }
    }

    /// Pages two at a time, re-pricing the first page's last lot to `newBid` before page two.
    private func walkRepricingCursorLot(sort: InventorySort, newBid: Int) throws -> [VehicleModel.ID] {
        var query = InventoryQuery()
        query.sort = sort
        var lots = pricedLots
        let first = try page(lots, query, after: nil, limit: 2)
        let cursorID = try #require(first.vehicles.last?.id)
        let index = try #require(lots.firstIndex { $0.id == cursorID })
        lots[index].currentBid = newBid
        lots[index].bidCount = 1

        var seen = first.vehicles.map(\.id)
        var cursor = first.nextCursor
        var pages = 0
        while let current = cursor, pages < 10 {
            let next = try page(lots, query, after: current, limit: 2)
            seen += next.vehicles.map(\.id)
            cursor = next.nextCursor
            pages += 1
        }
        #expect(pages < 10, "paging never ended")
        return seen
    }

    @Test("LIST-7: a cursor lot re-priced up or down between pages skips no rows (price low→high)")
    func repricedCursorAscending() throws {
        for newBid in [9_000, 500] {
            let seen = try walkRepricingCursorLot(sort: .priceLowToHigh, newBid: newBid)
            #expect(Set(seen).count == 5)
        }
    }

    @Test("LIST-7: a cursor lot re-priced up or down between pages skips no rows (price high→low)")
    func repricedCursorDescending() throws {
        for newBid in [9_000, 500] {
            let seen = try walkRepricingCursorLot(sort: .priceHighToLow, newBid: newBid)
            #expect(Set(seen).count == 5)
        }
    }

    @Test("LIST-7: under ending soonest, a cursor lot that ends between pages skips no live or upcoming rows")
    func cursorLotEndsBetweenPages() throws {
        // Active lots ending 1 h, 2 h, … 4 h after `now`, plus one upcoming lot.
        let active = (1...4).map { hours in
            VehicleModel.fixture(auctionStart: now.addingTimeInterval(TestDates.hours(Double(hours) - 72)))
        }
        let upcoming = VehicleModel.fixture(auctionStart: now.addingTimeInterval(TestDates.hours(1)))
        let lots = active + [upcoming]
        let query = InventoryQuery()

        let first = try page(lots, query, after: nil, limit: 1)
        #expect(first.vehicles.map(\.id) == [active[0].id])

        // 90 minutes later the cursor lot has ended and sorts last.
        let later = now.addingTimeInterval(TestDates.hours(1.5))
        let results = query.apply(to: lots, now: later)
        let second = try Paginator.page(of: results, after: first.nextCursor, limit: 10) {
            query.position(of: $0, now: later)
        }

        #expect(second.vehicles.map(\.id) == [active[1].id, active[2].id, active[3].id, upcoming.id, active[0].id])
        #expect(second.nextCursor == nil)
    }

    @Test("LIST-3 / TIME-4: the next status change is the earliest start or end after now, only with a status filter")
    func nextStatusChange() {
        let live = VehicleModel.fixture(auctionStart: now.addingTimeInterval(-TestDates.hours(70)))
        let upcoming = VehicleModel.fixture(auctionStart: now.addingTimeInterval(TestDates.hours(5)))
        var query = InventoryQuery()

        #expect(query.nextStatusChange(in: [live, upcoming], after: now) == nil)

        query.statuses = [.active]
        #expect(query.nextStatusChange(in: [live, upcoming], after: now) == live.auctionEnd)
        #expect(query.nextStatusChange(in: [upcoming], after: now) == upcoming.auctionStart)
    }

}
