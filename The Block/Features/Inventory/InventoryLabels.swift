import Foundation

/// Buyer-facing names for inventory sort orders, filters, and counts (spec LIST-3 … LIST-6).
///
/// Namespaced functions instead of extensions on the domain enums, so other features can
/// add their own wording without clashing.
enum InventoryLabels {

    /// Sort menu title, e.g. `Ending soonest`.
    static func title(for sort: InventorySort) -> String {
        switch sort {
        case .endingSoonest: Localizable.endingSoonest
        case .priceLowToHigh: Localizable.priceLowToHigh
        case .priceHighToLow: Localizable.priceHighToLow
        case .newestYear: Localizable.newestYear
        case .lowestMileage: Localizable.lowestMileage
        }
    }

    /// Status filter title, e.g. `Upcoming`, `Active`, `Ended`.
    static func title(for status: StatusFilter) -> String {
        switch status {
        case .upcoming: Localizable.upcoming
        case .active: Localizable.active
        case .ended: Localizable.ended
        }
    }

    /// Body style title, e.g. `SUV`, `Sedan`.
    static func title(for bodyStyle: BodyStyle) -> String {
        bodyStyle == .suv ? bodyStyle.rawValue : bodyStyle.rawValue.capitalized
    }

    /// Fuel type title, e.g. `Electric`.
    static func title(for fuelType: FuelType) -> String {
        fuelType.rawValue.capitalized
    }

    /// Chip title for one active filter.
    static func title(for chip: InventoryViewModel.FilterChip) -> String {
        switch chip {
        case .status(let status): title(for: status)
        case .bodyStyle(let style): title(for: style)
        case .fuelType(let fuel): title(for: fuel)
        case .province(let province): province
        case .buyNowOnly: Localizable.buyNow
        }
    }

    /// Result count, e.g. `1 vehicle`, `142 vehicles` (spec LIST-6).
    static func resultCount(_ count: Int) -> String {
        count == 1 ? Localizable.oneVehicle : String(format: Localizable.vehiclesFormat, count)
    }

    /// Bid count, e.g. `No bids`, `1 bid`, `14 bids`.
    static func bidCount(_ count: Int) -> String {
        switch count {
        case 0: Localizable.noBids
        case 1: Localizable.oneBid
        default: String(format: Localizable.bidsFormat, count)
        }
    }

}

private enum Localizable {
    static let endingSoonest = "Ending soonest"
    static let priceLowToHigh = "Price: low to high"
    static let priceHighToLow = "Price: high to low"
    static let newestYear = "Newest year"
    static let lowestMileage = "Lowest km"
    static let upcoming = "Upcoming"
    static let active = "Active"
    static let ended = "Ended"
    static let buyNow = "Buy Now available"
    static let oneVehicle = "1 vehicle"
    static let vehiclesFormat = "%d vehicles"
    static let noBids = "No bids"
    static let oneBid = "1 bid"
    static let bidsFormat = "%d bids"
}
