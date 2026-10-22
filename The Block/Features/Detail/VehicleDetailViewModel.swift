import Foundation
import Observation

/// What the bottom action bar offers at a given moment (spec DETAIL-6, BID-11).
enum DetailActionBarState: Hashable, Sendable {
    /// Upcoming or active lot: place a bid from `minimumBid`; Buy Now only when `buyNowPrice` is set.
    case bidding(minimumBid: Int, buyNowPrice: Int?)
    /// Ended lot: show the outcome, no actions.
    case ended(EndedOutcome)
}

/// The buyer's own position on a lot, shown in the header (spec BID-6, BID-10).
enum BuyerMarker: Hashable, Sendable {
    case highBidder
    case purchased
}

/// One label/value pair in the specs grid (spec DETAIL-3).
struct SpecRow: Identifiable, Hashable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

/// Detail screen state for one vehicle (spec DETAIL-*).
///
/// Reads the vehicle live from the repository, so bids and purchases show up immediately
/// (spec BID-6). Business rules stay in `BiddingRules`; this type only shapes them for display.
@Observable
final class VehicleDetailViewModel {

    let vehicleID: VehicleModel.ID
    @ObservationIgnored let repository: VehicleRepositoryProtocol

    init(vehicleID: VehicleModel.ID, repository: VehicleRepositoryProtocol) {
        self.vehicleID = vehicleID
        self.repository = repository
    }

    /// Latest repository copy, so bids placed elsewhere show up immediately (spec BID-6).
    var vehicle: VehicleModel? { repository.vehicle(id: vehicleID) }

    func actionBar(at now: Date) -> DetailActionBarState? {
        guard let vehicle else { return nil }
        if case .ended(let outcome) = vehicle.status(at: now) {
            return .ended(outcome)
        }
        let buyNowPrice = BiddingRules.canBuyNow(vehicle, at: now) ? vehicle.buyNowPrice : nil
        return .bidding(minimumBid: BiddingRules.minimumNextBid(for: vehicle), buyNowPrice: buyNowPrice)
    }

    func buyerMarker(at now: Date) -> BuyerMarker? {
        guard let vehicle else { return nil }
        if vehicle.status(at: now) == .ended(.purchasedByYou) {
            return .purchased
        }
        return vehicle.isYouHighBidder ? .highBidder : nil
    }

    var priceLabel: String {
        guard let vehicle, vehicle.bidCount > 0, vehicle.currentBid != nil else { return Localizable.startingAt }
        return Localizable.currentBid
    }

    var priceAmount: String {
        guard let vehicle else { return "" }
        return Formatting.currency(vehicle.currentBid ?? vehicle.startingBid)
    }

    var bidCountText: String {
        let count = vehicle?.bidCount ?? 0
        return count == 1 ? Localizable.oneBid : Localizable.bids(count)
    }

    var specRows: [SpecRow] {
        guard let vehicle else { return [] }
        return [
            SpecRow(label: Localizable.engine, value: vehicle.engine),
            SpecRow(label: Localizable.transmission, value: vehicle.transmission.displayName),
            SpecRow(label: Localizable.drivetrain, value: vehicle.drivetrain.rawValue),
            SpecRow(label: Localizable.fuel, value: vehicle.fuelType.rawValue.capitalized),
            SpecRow(label: Localizable.odometer, value: Formatting.kilometres(vehicle.odometerKm)),
            SpecRow(label: Localizable.bodyStyle, value: vehicle.bodyStyle.displayName),
            SpecRow(label: Localizable.exterior, value: vehicle.exteriorColor),
            SpecRow(label: Localizable.interior, value: vehicle.interiorColor)
        ]
    }

    var conditionGradeText: String {
        guard let vehicle else { return "" }
        return String(format: "%.1f / 5", vehicle.conditionGrade)
    }

    var hasDamageNotes: Bool { !(vehicle?.damageNotes.isEmpty ?? true) }

    var isTitleFlagged: Bool {
        guard let vehicle else { return false }
        return vehicle.titleStatus != .clean
    }

    var titleStatusText: String { vehicle?.titleStatus.rawValue.capitalized ?? "" }

    var locationText: String {
        guard let vehicle else { return "" }
        return "\(vehicle.city), \(vehicle.province)"
    }

}

private extension Transmission {
    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual"
        case .cvt: "CVT"
        case .singleSpeed: "Single-speed"
        }
    }
}

private extension BodyStyle {
    var displayName: String {
        switch self {
        case .suv: "SUV"
        default: rawValue.capitalized
        }
    }
}

private enum Localizable {
    static let startingAt = "Starting at"
    static let currentBid = "Current bid"
    static let oneBid = "1 bid"
    static func bids(_ count: Int) -> String { "\(count) bids" }
    static let engine = "Engine"
    static let transmission = "Transmission"
    static let drivetrain = "Drivetrain"
    static let fuel = "Fuel"
    static let odometer = "Odometer"
    static let bodyStyle = "Body style"
    static let exterior = "Exterior"
    static let interior = "Interior"
}
