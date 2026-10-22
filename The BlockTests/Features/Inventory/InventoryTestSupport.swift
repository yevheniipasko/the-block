import Foundation
@testable import The_Block

/// 45 active lots with distinct prices (10_000, 10_100, …) and Buy Now prices.
@MainActor
let inventoryFleet: [VehicleModel] = (0..<45).map { index in
    .fixture(startingBid: 10_000 + index * 100, buyNowPrice: 50_000)
}

/// Runs a ViewModel's stream subscriptions like the view's `.task`s, cancelling them when the test ends.
@MainActor
final class InventoryObservers {

    private var tasks: [Task<Void, Never>] = []

    func start(_ viewModel: InventoryViewModel) {
        tasks.append(Task { await viewModel.observeLoadState() })
        tasks.append(Task { await viewModel.observeInventoryChanges() })
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

}

/// Fake server plus a loaded repository on it, so tests can push competing bids.
@MainActor
func makeInventoryStack(
    _ vehicles: [VehicleModel],
    clock: AuctionClockProtocol
) async -> (server: SimulatedAuctionDataSource, repository: VehicleRepository) {
    let server = SimulatedAuctionDataSource.stub(result: .success(vehicles), clock: clock)
    let repository = VehicleRepository(dataSource: server, clock: clock)
    await repository.load()
    return (server, repository)
}

/// Subscribed ViewModel with page one loaded, sorted by price so page order is deterministic.
@MainActor
func makeStartedInventory(
    repository: VehicleRepositoryProtocol,
    observers: InventoryObservers
) async -> InventoryViewModel {
    let viewModel = InventoryViewModel(repository: repository)
    observers.start(viewModel)
    await waitUntil { viewModel.isInventoryLoaded }
    await settle(viewModel)
    viewModel.query.sort = .priceLowToHigh
    await settle(viewModel)
    return viewModel
}

/// Lets the subscription tasks run until `condition` holds, a bounded number of times.
///
/// Feed updates are delivered on the main actor, so a busy loop would never see them.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        await Task.yield()
    }
}

/// Waits until no page request is in flight, following restarts.
@MainActor
func settle(_ viewModel: InventoryViewModel) async {
    while viewModel.pageStatus == .loading, let task = viewModel.loadTask {
        await task.value
    }
}

/// Scrolls to the last loaded row and waits for the next page.
@MainActor
func loadNextPage(_ viewModel: InventoryViewModel) async {
    guard let last = viewModel.loadedIDs.last else { return }
    viewModel.loadNextPageIfNeeded(currentID: last)
    await settle(viewModel)
}
