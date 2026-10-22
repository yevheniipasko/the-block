import Foundation

/// A vehicle listed in the auction, as the app works with it.
///
/// Built from `VehicleDto` in `Data/`. Dataset fields are immutable except the live auction
/// state (`currentBid`, `bidCount`) and the normalized `auctionStart`. The buyer's own
/// position (`yourBid`, `yourPurchasePrice`) starts as `nil`.
struct VehicleModel: Identifiable, Hashable, Sendable {

    let id: UUID
    let vin: String
    let year: Int
    let make: String
    let model: String
    let trim: String
    let bodyStyle: BodyStyle
    let exteriorColor: String
    let interiorColor: String
    let engine: String
    let transmission: Transmission
    let drivetrain: Drivetrain
    let odometerKm: Int
    let fuelType: FuelType
    let conditionGrade: Double
    let conditionReport: String
    let damageNotes: [String]
    let titleStatus: TitleStatus
    let province: String
    let city: String
    var auctionStart: Date
    let startingBid: Int
    let reservePrice: Int?
    let buyNowPrice: Int?
    let images: [URL]
    let sellingDealership: String
    let lot: String
    var currentBid: Int?
    var bidCount: Int

    /// Amount of the buyer's latest bid on this vehicle, if any.
    var yourBid: Int?
    /// Price paid through Buy Now, if the buyer bought this vehicle.
    var yourPurchasePrice: Int?

    /// Display name: year, make, model, and trim.
    var title: String { "\(year) \(make) \(model) \(trim)" }
    /// When the auction closes: the normalized start plus the 72 h duration (spec TIME-2).
    var auctionEnd: Date { auctionStart.addingTimeInterval(AuctionSchedule.duration) }
    /// Whether the buyer's latest bid is still the current bid (spec BID-6).
    var isYouHighBidder: Bool { yourBid != nil && yourBid == currentBid }
    /// Whether the buyer bought this lot through Buy Now (spec BID-10).
    var isPurchasedByYou: Bool { yourPurchasePrice != nil }
    /// The buyer bid on this lot but someone else now holds the high bid (spec LIVE-3).
    var isYouOutbid: Bool { yourBid != nil && !isYouHighBidder && !isPurchasedByYou }

}

enum BodyStyle: String, Sendable, CaseIterable {
    case suv = "SUV"
    case coupe
    case hatchback
    case sedan
    case truck
}

enum Transmission: String, Sendable, CaseIterable {
    case automatic
    case manual
    case cvt = "CVT"
    case singleSpeed = "single-speed"
}

enum Drivetrain: String, Sendable, CaseIterable {
    case fourWheel = "4WD"
    case allWheel = "AWD"
    case frontWheel = "FWD"
    case rearWheel = "RWD"
}

enum FuelType: String, Sendable, CaseIterable {
    case gasoline
    case diesel
    case hybrid
    case electric
}

enum TitleStatus: String, Sendable, CaseIterable {
    case clean
    case rebuilt
    case salvage
}
