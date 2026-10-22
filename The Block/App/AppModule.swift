import Foundation
import Swinject

/// The only place that touches Swinject: owns the container, registers every dependency,
/// and hands fully built objects to the rest of the app. Nothing else sees the container.
final class AppModule: ViewModelFactoryProtocol {

    private let container = Container()
    private let launchOptions: LaunchOptions

    /// - Parameter launchOptions: Launch-time switches (UI tests); `.standard` for a normal launch.
    init(launchOptions: LaunchOptions = .standard) {
        self.launchOptions = launchOptions
        registerData()
        registerViewModels()
        registerRouters()
    }

    /// Shared repository; ViewModels receive it through `init` from the factories below.
    var repository: VehicleRepositoryProtocol { resolve(VehicleRepositoryProtocol.self) }

    /// App-wide router, created once and shared.
    var router: InventoryRouterProtocol { resolve(InventoryRouterProtocol.self) }

    /// App-wide outbid banner state, created once and shared (spec ALERT-1).
    var outbidAlertCenter: OutbidAlertCenter { resolve(OutbidAlertCenter.self) }

    /// Loads the inventory; called once when the app's root view appears.
    func start() async {
        await repository.load()
    }

    // MARK: - ViewModelFactoryProtocol

    /// Builds the inventory ViewModel on the shared repository.
    func makeInventoryViewModel() -> InventoryViewModel {
        resolve(InventoryViewModel.self)
    }

    /// Builds a fresh detail ViewModel for one vehicle.
    func makeVehicleDetailViewModel(vehicleID: VehicleModel.ID) -> VehicleDetailViewModel {
        resolve(VehicleDetailViewModel.self, argument: vehicleID)
    }

    /// Builds a fresh bid / Buy Now ViewModel for one vehicle.
    func makeBidViewModel(vehicleID: VehicleModel.ID) -> BidViewModel {
        resolve(BidViewModel.self, argument: vehicleID)
    }

    // MARK: - Registrations

    private func registerData() {
        container.register(AuctionClockProtocol.self) { _ in
            SystemAuctionClock()
        }
        .inObjectScope(.container)

        container.register(VehicleDataSourceProtocol.self) { [unowned self] _ in
            let loader = BundledVehicleLoader()
            return SimulatedAuctionDataSource(
                loadSnapshot: { try loader.loadVehicles() },
                clock: resolve(AuctionClockProtocol.self),
                latency: Constants.actionLatency,
                market: launchOptions.marketSettings,
                generator: SystemRandomNumberGenerator(),
                seedsDemoPositions: true
            )
        }
        .inObjectScope(.container)

        container.register(VehicleRepositoryProtocol.self) { [unowned self] _ in
            VehicleRepository(
                dataSource: resolve(VehicleDataSourceProtocol.self),
                clock: resolve(AuctionClockProtocol.self),
                pageLatency: Constants.pageLatency
            )
        }
        .inObjectScope(.container)
    }

    private func registerViewModels() {
        container.register(InventoryViewModel.self) { [unowned self] _ in
            InventoryViewModel(repository: repository)
        }
        .inObjectScope(.container)

        container.register(VehicleDetailViewModel.self) { [unowned self] (_, vehicleID: VehicleModel.ID) in
            VehicleDetailViewModel(vehicleID: vehicleID, repository: repository)
        }
        .inObjectScope(.transient)

        container.register(BidViewModel.self) { [unowned self] (_, vehicleID: VehicleModel.ID) in
            BidViewModel(vehicleID: vehicleID, repository: repository)
        }
        .inObjectScope(.transient)

        container.register(OutbidAlertCenter.self) { [unowned self] _ in
            OutbidAlertCenter(repository: repository)
        }
        .inObjectScope(.container)
    }

    private func registerRouters() {
        container.register(InventoryRouterProtocol.self) { [unowned self] _ in
            InventoryRouter(factory: self)
        }
        .inObjectScope(.container)
    }

    // MARK: - Resolution

    /// A missing registration is a programming error, caught on first launch.
    private func resolve<Service>(_ type: Service.Type) -> Service {
        guard let service = container.resolve(type) else {
            preconditionFailure("AppModule: no registration for \(type)")
        }
        return service
    }

    private func resolve<Service, Argument>(_ type: Service.Type, argument: Argument) -> Service {
        guard let service = container.resolve(type, argument: argument) else {
            preconditionFailure("AppModule: no registration for \(type) with \(Argument.self)")
        }
        return service
    }

}

private enum Constants {
    /// Simulated network delay for each inventory page.
    static let pageLatency: Duration = .milliseconds(350)
    /// Simulated network delay for placing a bid or buying now.
    static let actionLatency: Duration = .milliseconds(600)
}
