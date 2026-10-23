//
//  VehicleDetailViewModel.swift
//  The Block
//
//  Detail screen state and display shaping: live lot copy, action bar state,
//  buyer marker, price text and spec rows (spec DETAIL-*, BID-6).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

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
    /// The buyer holds the current high bid.
    case highBidder
    /// The buyer bid but someone else now leads; shown on live lots only.
    case outbid
    /// The lot ended as "Purchased by you".
    case purchased
}

/// One label/value pair in the specs grid (spec DETAIL-3).
struct SpecRow: Identifiable, Hashable, Sendable {
    /// Caption above the value, e.g. `Engine`; also the row's identity.
    let label: String
    /// Display value, e.g. `Automatic`.
    let value: String
    /// SF Symbol shown beside the cell.
    let systemImage: String
    var id: String { label }
}

/// Detail screen state for one vehicle (spec DETAIL-*).
///
/// Keeps its own copy of the vehicle, refreshed from `repository.vehicleUpdates(id:)` while the
/// screen observes it, so your bids and other bidders' bids show up live (spec BID-6, LIVE-1,
/// LIVE-3). Business rules stay in `BiddingRules`; this type only shapes them for display.
@Observable
final class VehicleDetailViewModel {

    let vehicleID: VehicleModel.ID
    @ObservationIgnored let repository: VehicleRepositoryProtocol

    /// Latest known copy of the lot; `nil` when it is not in the inventory.
    private(set) var vehicle: VehicleModel?

    /// Creates the detail state for one lot, starting from the repository's current copy.
    init(vehicleID: VehicleModel.ID, repository: VehicleRepositoryProtocol) {
        self.vehicleID = vehicleID
        self.repository = repository
        self.vehicle = repository.vehicle(id: vehicleID)
    }

    /// Keeps `vehicle` current until the calling task is cancelled (spec LIVE-1, LIVE-3, BID-6).
    ///
    /// Assigns every value from `repository.vehicleUpdates(id:)` — the current copy first, then each
    /// change from your bids or other bidders — so the header, outbid marker, and action bar minimum
    /// follow the lot live. Called from the view's `.task`, which cancels it when the screen goes away.
    func observeVehicle() async {
        for await update in repository.vehicleUpdates(id: vehicleID) {
            vehicle = update
        }
    }

    /// What the bottom action bar shows at `now` (spec DETAIL-6, TIME-4, BID-11).
    ///
    /// Upcoming and active lots offer a bid from `BiddingRules.minimumNextBid`; Buy Now is added
    /// only when `BiddingRules.canBuyNow` allows it. Ended lots return their outcome instead.
    /// - Returns: `nil` when the vehicle is missing.
    func actionBar(at now: Date) -> DetailActionBarState? {
        guard let vehicle else { return nil }
        if case .ended(let outcome) = vehicle.status(at: now) {
            return .ended(outcome)
        }
        let buyNowPrice = BiddingRules.canBuyNow(vehicle, at: now) ? vehicle.buyNowPrice : nil
        return .bidding(minimumBid: BiddingRules.minimumNextBid(for: vehicle), buyNowPrice: buyNowPrice)
    }

    /// The buyer's own position at `now`: purchased, high bidder, outbid, or `nil` (spec BID-6, BID-10, LIVE-3).
    func buyerMarker(at now: Date) -> BuyerMarker? {
        guard let vehicle else { return nil }
        if vehicle.status(at: now) == .ended(.purchasedByYou) {
            return .purchased
        }
        if vehicle.isYouHighBidder {
            return .highBidder
        }
        // Once the lot has ended, the outcome bar tells the story; "outbid" is no longer actionable.
        guard !vehicle.status(at: now).isEnded else { return nil }
        return vehicle.isYouOutbid ? .outbid : nil
    }

    /// "Purchased for" after Buy Now, "Current bid" once the lot has bids, otherwise "Starting at"
    /// (spec DETAIL-2, BID-10).
    var priceLabel: String {
        guard let vehicle else { return Localizable.startingAt }
        if vehicle.isPurchasedByYou {
            return Localizable.purchasedFor
        }
        guard vehicle.bidCount > 0, vehicle.currentBid != nil else { return Localizable.startingAt }
        return Localizable.currentBid
    }

    /// The Buy Now price paid, else the current bid, else the starting bid, as CAD.
    var priceAmount: String {
        guard let vehicle else { return "" }
        if let purchasePrice = vehicle.yourPurchasePrice {
            return Formatting.currency(purchasePrice)
        }
        return Formatting.currency(vehicle.currentBid ?? vehicle.startingBid)
    }

    /// Bid count with the right plural, e.g. `No bids`, `1 bid`, `14 bids`.
    var bidCountText: String {
        Formatting.bidCount(vehicle?.bidCount ?? 0)
    }

    /// Spec grid rows in display order; the VIN is shown separately with a copy button (spec DETAIL-3).
    var specRows: [SpecRow] {
        guard let vehicle else { return [] }
        return [
            SpecRow(label: Localizable.engine, value: vehicle.engine, systemImage: "engine.combustion"),
            SpecRow(label: Localizable.transmission, value: vehicle.transmission.displayName, systemImage: "gearshape"),
            SpecRow(
                label: Localizable.drivetrain,
                value: vehicle.drivetrain.rawValue,
                systemImage: "car.rear.road.lane"
            ),
            SpecRow(label: Localizable.fuel, value: vehicle.fuelType.rawValue.capitalized, systemImage: "fuelpump"),
            SpecRow(
                label: Localizable.odometer,
                value: Formatting.kilometres(vehicle.odometerKm),
                systemImage: "gauge.with.dots.needle.50percent"
            ),
            SpecRow(label: Localizable.bodyStyle, value: vehicle.bodyStyle.displayName, systemImage: "car.side"),
            SpecRow(label: Localizable.exterior, value: vehicle.exteriorColor, systemImage: "paintpalette"),
            SpecRow(label: Localizable.interior, value: vehicle.interiorColor, systemImage: "steeringwheel")
        ]
    }

    /// Condition grade as `x.x / 5` (spec DETAIL-4).
    var conditionGradeText: String {
        guard let vehicle else { return "" }
        return String(format: "%.1f / 5", vehicle.conditionGrade)
    }

    /// Whether the lot has damage notes; `false` shows "No damage reported" (spec DETAIL-4).
    var hasDamageNotes: Bool { !(vehicle?.damageNotes.isEmpty ?? true) }

    /// Rebuilt and salvage titles are flagged with warning styling (spec DETAIL-4).
    var isTitleFlagged: Bool {
        guard let vehicle else { return false }
        return vehicle.titleStatus != .clean
    }

    /// Title status for display, e.g. `Rebuilt` (spec DETAIL-4).
    var titleStatusText: String { vehicle?.titleStatus.rawValue.capitalized ?? "" }

    /// Seller location as `City, Province` (spec DETAIL-5).
    var locationText: String {
        guard let vehicle else { return "" }
        return "\(vehicle.city), \(vehicle.province)"
    }

}

private extension Transmission {
    /// Readable transmission name, e.g. `CVT`, `Single-speed`.
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
    /// Body style for display: `SUV` in capitals, the rest capitalised.
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
    static let purchasedFor = "Purchased for"
    static let engine = "Engine"
    static let transmission = "Transmission"
    static let drivetrain = "Drivetrain"
    static let fuel = "Fuel"
    static let odometer = "Odometer"
    static let bodyStyle = "Body style"
    static let exterior = "Exterior"
    static let interior = "Interior"
}
