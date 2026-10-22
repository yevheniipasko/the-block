import Foundation

/// Mirrors one entry of `vehicles.json` exactly. Never leaves `Data/`.
struct VehicleDto: Decodable, Sendable {

    let id: String
    let vin: String
    let year: Int
    let make: String
    let model: String
    let trim: String
    let bodyStyle: String
    let exteriorColor: String
    let interiorColor: String
    let engine: String
    let transmission: String
    let drivetrain: String
    let odometerKm: Int
    let fuelType: String
    let conditionGrade: Double
    let conditionReport: String
    let damageNotes: [String]
    let titleStatus: String
    let province: String
    let city: String
    let auctionStart: String
    let startingBid: Int
    let reservePrice: Int?
    let buyNowPrice: Int?
    let images: [String]
    let sellingDealership: String
    let lot: String
    let currentBid: Int?
    let bidCount: Int

    enum CodingKeys: String, CodingKey {
        case id, vin, year, make, model, trim, engine, transmission, drivetrain
        case province, city, images, lot
        case bodyStyle = "body_style"
        case exteriorColor = "exterior_color"
        case interiorColor = "interior_color"
        case odometerKm = "odometer_km"
        case fuelType = "fuel_type"
        case conditionGrade = "condition_grade"
        case conditionReport = "condition_report"
        case damageNotes = "damage_notes"
        case titleStatus = "title_status"
        case auctionStart = "auction_start"
        case startingBid = "starting_bid"
        case reservePrice = "reserve_price"
        case buyNowPrice = "buy_now_price"
        case sellingDealership = "selling_dealership"
        case currentBid = "current_bid"
        case bidCount = "bid_count"
    }

}

enum VehicleMappingError: Error, Equatable {
    case invalidField(name: String, value: String, lot: String)
}

extension VehicleDto {

    /// Parses raw strings into typed values; any unexpected value fails loudly with its lot number.
    func toModel() throws -> VehicleModel {
        VehicleModel(
            id: try require(UUID(uuidString: id), field: "id", raw: id),
            vin: vin,
            year: year,
            make: make,
            model: model,
            trim: trim,
            bodyStyle: try require(BodyStyle(rawValue: bodyStyle), field: "body_style", raw: bodyStyle),
            exteriorColor: exteriorColor,
            interiorColor: interiorColor,
            engine: engine,
            transmission: try require(Transmission(rawValue: transmission), field: "transmission", raw: transmission),
            drivetrain: try require(Drivetrain(rawValue: drivetrain), field: "drivetrain", raw: drivetrain),
            odometerKm: odometerKm,
            fuelType: try require(FuelType(rawValue: fuelType), field: "fuel_type", raw: fuelType),
            conditionGrade: conditionGrade,
            conditionReport: conditionReport,
            damageNotes: damageNotes,
            titleStatus: try require(TitleStatus(rawValue: titleStatus), field: "title_status", raw: titleStatus),
            province: province,
            city: city,
            auctionStart: try require(Self.parseDate(auctionStart), field: "auction_start", raw: auctionStart),
            startingBid: startingBid,
            reservePrice: reservePrice,
            buyNowPrice: buyNowPrice,
            images: images.compactMap(URL.init(string:)),
            sellingDealership: sellingDealership,
            lot: lot,
            currentBid: currentBid,
            bidCount: bidCount
        )
    }

    private func require<Value>(_ value: Value?, field: String, raw: String) throws -> Value {
        guard let value else {
            throw VehicleMappingError.invalidField(name: field, value: raw, lot: lot)
        }
        return value
    }

    /// `auction_start` has no timezone (e.g. `2026-04-05T14:00:00`); it is read as local time.
    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }

}
