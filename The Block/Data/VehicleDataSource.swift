import Foundation

/// One message on the vehicle feed, as a socket would push it (spec LIVE-1).
enum VehicleFeedEvent: Sendable {
    /// Full inventory; always the first event after connecting.
    case snapshot([VehicleModel])
    /// One lot changed (a bid, a purchase, another bidder).
    case updated(VehicleModel)
}

/// Remote side of the auction: a live feed plus request/response actions.
///
/// Returns app models only — DTOs stay inside `Data/`. Today it is simulated in-process
/// (`SimulatedAuctionDataSource`); a WebSocket + HTTP client would conform later.
protocol VehicleDataSourceProtocol: Sendable {

    /// Opens the live feed: `.snapshot` first, then `.updated` whenever any lot changes.
    ///
    /// - Throws (from the stream): the error that prevented the initial snapshot.
    func vehicleFeed() -> AsyncThrowingStream<VehicleFeedEvent, Error>

    /// Sends a bid for the buyer; the server validates it with `BiddingRules` and also pushes the
    /// updated lot over the feed.
    ///
    /// - Throws: `BidRejection` when the server refuses the bid.
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async throws -> VehicleModel

    /// Buys the lot at its Buy Now price; the updated lot is also pushed over the feed.
    ///
    /// - Throws: `BidRejection.buyNowUnavailable` / `.vehicleNotFound`.
    func buyNow(_ id: VehicleModel.ID) async throws -> VehicleModel

}

enum VehicleDataSourceError: Error, Equatable {
    case resourceNotFound(name: String)
}

/// Reads the bundled `vehicles.json` snapshot (spec DATA-1, DATA-2).
struct BundledVehicleLoader: Sendable {

    private let bundle: Bundle
    private let resourceName: String

    /// - Parameters:
    ///   - bundle: Bundle containing the JSON; the app bundle by default.
    ///   - resourceName: File name without the `.json` extension.
    init(bundle: Bundle = .main, resourceName: String = "vehicles") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    /// Decodes every vehicle in the file.
    ///
    /// - Throws: `VehicleDataSourceError.resourceNotFound`, file read errors, `DecodingError`,
    ///   or `VehicleMappingError` for an unexpected value.
    func loadVehicles() throws -> [VehicleModel] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw VehicleDataSourceError.resourceNotFound(name: resourceName)
        }
        return try VehicleDecoder.decode(try Data(contentsOf: url))
    }

}

/// Decodes `[VehicleDto]` and maps each entry to `VehicleModel`.
enum VehicleDecoder {

    /// Decodes the dataset and maps every DTO; one bad entry fails the whole load (spec DATA-2).
    static func decode(_ data: Data) throws -> [VehicleModel] {
        try JSONDecoder()
            .decode([VehicleDto].self, from: data)
            .map { try $0.toModel() }
    }

}
