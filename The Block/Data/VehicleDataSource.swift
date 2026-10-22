import Foundation

/// Source of vehicles. Today a bundled JSON file; a remote API would conform later.
/// Returns app models only — DTOs stay inside `Data/`.
protocol VehicleDataSourceProtocol: Sendable {
    func loadVehicles() async throws -> [VehicleModel]
}

enum VehicleDataSourceError: Error, Equatable {
    case resourceNotFound(name: String)
}

/// Loads `vehicles.json` from the app bundle (spec DATA-1, DATA-2).
struct BundledJSONDataSource: VehicleDataSourceProtocol {

    private let bundle: Bundle
    private let resourceName: String

    init(bundle: Bundle = .main, resourceName: String = "vehicles") {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    func loadVehicles() async throws -> [VehicleModel] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw VehicleDataSourceError.resourceNotFound(name: resourceName)
        }
        return try VehicleDecoder.decode(try Data(contentsOf: url))
    }

}

/// Decodes `[VehicleDto]` and maps each entry to `VehicleModel`.
enum VehicleDecoder {

    static func decode(_ data: Data) throws -> [VehicleModel] {
        try JSONDecoder()
            .decode([VehicleDto].self, from: data)
            .map { try $0.toModel() }
    }

}
