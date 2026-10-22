import Foundation
import Swinject

/// The only place that touches Swinject: owns the container, registers every dependency,
/// and hands fully built objects to the rest of the app. Nothing else sees the container.
final class AppModule {

    private let container = Container()

    init() {
        registerData()
    }

    /// Shared repository; feature ViewModels receive it through `init` from the factories added here.
    var repository: VehicleRepositoryProtocol { resolve(VehicleRepositoryProtocol.self) }

    func start() async {
        await repository.load()
    }

    private func registerData() {
        container.register(AuctionClockProtocol.self) { _ in
            SystemAuctionClock()
        }
        .inObjectScope(.container)

        container.register(VehicleDataSourceProtocol.self) { _ in
            BundledJSONDataSource()
        }
        .inObjectScope(.container)

        container.register(VehicleRepositoryProtocol.self) { [unowned self] _ in
            VehicleRepository(
                dataSource: resolve(VehicleDataSourceProtocol.self),
                clock: resolve(AuctionClockProtocol.self)
            )
        }
        .inObjectScope(.container)
    }

    /// A missing registration is a programming error, caught on first launch.
    private func resolve<Service>(_ type: Service.Type) -> Service {
        guard let service = container.resolve(type) else {
            preconditionFailure("AppModule: no registration for \(type)")
        }
        return service
    }

}
