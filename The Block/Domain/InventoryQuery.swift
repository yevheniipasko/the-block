//
//  InventoryQuery.swift
//  The Block
//
//  Inventory search, filter, and sort options and how they are applied to vehicles.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation

/// Status groups a buyer can filter by (spec LIST-3).
enum StatusFilter: String, Sendable, CaseIterable {
    case upcoming
    case active
    case ended

    /// Whether a vehicle's status at `now` falls in this group.
    func matches(_ status: AuctionStatus) -> Bool {
        switch (self, status) {
        case (.upcoming, .upcoming), (.active, .active), (.ended, .ended): true
        default: false
        }
    }
}

/// Inventory sort orders (spec LIST-4).
enum InventorySort: String, Sendable, CaseIterable {
    case endingSoonest
    case priceLowToHigh
    case priceHighToLow
    case newestYear
    case lowestMileage
}

/// Search + filters + sort for the inventory, applied "server-side" before paging (spec LIST-2 … LIST-4).
struct InventoryQuery: Hashable, Sendable {

    /// Free text; every space-separated term must match (spec LIST-2).
    var searchText = ""
    var bodyStyles: Set<BodyStyle> = []
    var fuelTypes: Set<FuelType> = []
    /// Province names as stored in the data.
    var provinces: Set<String> = []
    /// Status groups evaluated at the `now` passed to `apply(to:now:)`.
    var statuses: Set<StatusFilter> = []
    /// Keeps only lots that have a Buy Now price.
    var buyNowOnly = false
    var sort: InventorySort = .endingSoonest

    /// Filters and sorts `vehicles` as seen at `now`. Empty filter sets mean "any".
    ///
    /// Search is case-insensitive over make, model, trim, year, lot, VIN, and dealership.
    /// Ties keep a stable order by lot, then ID, so pages never shuffle between requests.
    func apply(to vehicles: [VehicleModel], now: Date) -> [VehicleModel] {
        vehicles
            .filter { matches($0, now: now) }
            .sorted { position(of: $0, now: now) < position(of: $1, now: now) }
    }

    /// Where `vehicle` sits in this query's order at `now`; also the paging boundary (spec LIST-7).
    func position(of vehicle: VehicleModel, now: Date) -> SortPosition {
        SortPosition(key: sortKey(vehicle, now: now), lot: vehicle.lot, id: vehicle.id)
    }

    /// When this query's results next change just because time passes (spec LIST-3, TIME-4).
    ///
    /// That is the earliest auction start or end after `now` among `vehicles`. `nil` when no
    /// status filter is on (results then don't depend on time) or no lot changes status later.
    func nextStatusChange(in vehicles: [VehicleModel], after now: Date) -> Date? {
        guard !statuses.isEmpty else { return nil }
        return vehicles
            .flatMap { [$0.auctionStart, $0.auctionEnd] }
            .filter { $0 > now }
            .min()
    }

    /// Whether a vehicle passes every active filter and the search text.
    private func matches(_ vehicle: VehicleModel, now: Date) -> Bool {
        if !bodyStyles.isEmpty, !bodyStyles.contains(vehicle.bodyStyle) { return false }
        if !fuelTypes.isEmpty, !fuelTypes.contains(vehicle.fuelType) { return false }
        if !provinces.isEmpty, !provinces.contains(vehicle.province) { return false }
        if buyNowOnly, vehicle.buyNowPrice == nil { return false }
        if !statuses.isEmpty {
            let status = vehicle.status(at: now)
            guard statuses.contains(where: { $0.matches(status) }) else { return false }
        }
        return matchesSearch(vehicle)
    }

    /// Whether every search term appears in the vehicle's searchable fields; empty search matches all.
    private func matchesSearch(_ vehicle: VehicleModel) -> Bool {
        let terms = searchText.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = [
            vehicle.make, vehicle.model, vehicle.trim, String(vehicle.year),
            vehicle.lot, vehicle.vin, vehicle.sellingDealership
        ].joined(separator: " ")
        return terms.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }

    /// Smaller key sorts first.
    private func sortKey(_ vehicle: VehicleModel, now: Date) -> Double {
        let price = Double(vehicle.currentBid ?? vehicle.startingBid)
        switch sort {
        case .endingSoonest: return endingSoonestKey(vehicle, now: now)
        case .priceLowToHigh: return price
        case .priceHighToLow: return -price
        case .newestYear: return -Double(vehicle.year)
        case .lowestMileage: return Double(vehicle.odometerKm)
        }
    }

    /// Active by end time, then upcoming by start time, ended last (spec LIST-4).
    private func endingSoonestKey(_ vehicle: VehicleModel, now: Date) -> Double {
        let groupSpan = 1e12
        switch vehicle.status(at: now) {
        case .active(let endsAt): return endsAt.timeIntervalSince1970
        case .upcoming(let startsAt): return groupSpan + startsAt.timeIntervalSince1970
        case .ended: return 2 * groupSpan + vehicle.auctionEnd.timeIntervalSince1970
        }
    }

}
