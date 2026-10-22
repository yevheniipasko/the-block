import Foundation

/// Source of vehicles. Today a bundled JSON file; a remote API would conform later.
/// Returns app models only — DTOs stay inside `Data/`.
protocol VehicleDataSourceProtocol: Sendable {
    /// Loads every vehicle, already mapped to app models (spec DATA-1).
    ///
    /// Auction starts are returned as stored in the source; normalization happens in the repository.
    ///
    /// - Throws: An error when the source is missing or any entry fails to decode or map (spec DATA-2).
    func loadVehicles() async throws -> [VehicleModel]
}

enum VehicleDataSourceError: Error, Equatable {
    case resourceNotFound(name: String)
}

/// Loads `vehicles.json` from the app bundle (spec DATA-1, DATA-2).
struct BundledJSONDataSource: VehicleDataSourceProtocol {

    private let bundle: Bundle
    private let resourceName: String

    /// Creates a data source reading `<resourceName>.json` from `bundle`.
    ///
    /// Tests pass their own bundle and resource name to load fixtures.
    init(bundle: Bundle = .main, resourceName: String = "vehicles") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    /// Reads the bundled JSON file and decodes it with `VehicleDecoder`.
    ///
    /// - Throws: `VehicleDataSourceError.resourceNotFound` when the file is not in the bundle,
    ///   or the underlying read, decoding, or mapping error.
    func loadVehicles() async throws -> [VehicleModel] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw VehicleDataSourceError.resourceNotFound(name: resourceName)
        }
        return try VehicleDecoder.decode(try Data(contentsOf: url))
    }

}

/// Decodes `[VehicleDto]` and maps each entry to `VehicleModel`.
enum VehicleDecoder {

    /// Decodes a JSON array of vehicles and maps each one to `VehicleModel` (spec DATA-1, DATA-2).
    ///
    /// All-or-nothing: one malformed entry fails the whole load, so the app shows an error state
    /// instead of a partial list (spec DATA-3).
    ///
    /// - Throws: `DecodingError` for invalid JSON or `VehicleMappingError` for an unexpected field value.
    static func decode(_ data: Data) throws -> [VehicleModel] {
        try JSONDecoder()
            .decode([VehicleDto].self, from: data)
            .map { try $0.toModel() }
    }

}
