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

    var searchText = ""
    var bodyStyles: Set<BodyStyle> = []
    var fuelTypes: Set<FuelType> = []
    var provinces: Set<String> = []
    var statuses: Set<StatusFilter> = []
    var buyNowOnly = false
    var sort: InventorySort = .endingSoonest

    /// Filters and sorts `vehicles` as seen at `now`. Empty filter sets mean "any".
    ///
    /// Search is case-insensitive over make, model, trim, year, lot, VIN, and dealership.
    /// Ties keep a stable order by lot so pages never shuffle between requests.
    func apply(to vehicles: [VehicleModel], now: Date) -> [VehicleModel] {
        vehicles
            .filter { matches($0, now: now) }
            .sorted { lhs, rhs in
                let left = sortKey(lhs, now: now)
                let right = sortKey(rhs, now: now)
                return left == right ? lhs.lot < rhs.lot : left < right
            }
    }

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
