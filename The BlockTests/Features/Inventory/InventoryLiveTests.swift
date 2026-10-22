import Foundation
import Testing
@testable import The_Block

/// Real repository whose page requests can be made to fail on demand.
@MainActor
private final class AttemptCounter {
    var count = 0
}

/// Inventory screen on the live feed: load-state stream, in-place row updates, outbid (spec LIVE-*).
@MainActor
struct InventoryLiveTests {

    private let clock = FixedClock(now: TestDates.reference)
    private let fleet = inventoryFleet
    private let observers = InventoryObservers()

    private func makeStack(
        _ vehicles: [VehicleModel]
    ) async -> (server: SimulatedAuctionDataSource, repository: VehicleRepository) {
        await makeInventoryStack(vehicles, clock: clock)
    }

    private func makeRepository(_ vehicles: [VehicleModel]) async -> VehicleRepository {
        await makeStack(vehicles).repository
    }

    private func makeStartedViewModel(repository: VehicleRepositoryProtocol) async -> InventoryViewModel {
        await makeStartedInventory(repository: repository, observers: observers)
    }

    @Test("LIVE-1 / UX-5: the load-state stream drives loading, then loaded, then page one")
    func loadStateStreamStartsFirstPage() async {
        let repository = VehicleRepository.stubbed(result: .success(fleet), clock: clock)
        let viewModel = InventoryViewModel(repository: repository)
        observers.start(viewModel)
        await waitUntil { false }
        #expect(viewModel.loadState == .idle)
        #expect(viewModel.content == .loading)
        #expect(viewModel.loadTask == nil)

        await repository.load()
        await waitUntil { viewModel.isInventoryLoaded }
        await settle(viewModel)

        #expect(viewModel.content == .results)
        #expect(viewModel.loadedIDs.count == 20)
        #expect(viewModel.totalCount == 45)
    }

    @Test("LIVE-4 / DATA-3: a failed feed shows the error, and retry reconnects and loads page one")
    func failedFeedRetryReconnects() async {
        let attempts = AttemptCounter()
        let fleet = fleet
        let server = SimulatedAuctionDataSource(
            loadSnapshot: {
                attempts.count += 1
                if attempts.count == 1 { throw StubError() }
                return fleet
            },
            clock: clock,
            latency: .zero,
            market: nil,
            generator: SeededGenerator(seed: 1)
        )
        let repository = VehicleRepository(dataSource: server, clock: clock)
        await repository.load()
        let viewModel = InventoryViewModel(repository: repository)
        observers.start(viewModel)
        await waitUntil { viewModel.loadState != .idle }

        guard case .loadFailed = viewModel.content else {
            Issue.record("Expected loadFailed, got \(viewModel.content)")
            return
        }

        await viewModel.retryLoad()
        await waitUntil { viewModel.isInventoryLoaded }
        await settle(viewModel)

        #expect(attempts.count == 2)
        #expect(viewModel.content == .results)
        #expect(viewModel.loadedIDs.count == 20)
    }

    @Test("LIVE-1 / LIVE-2: a competing bid replaces its loaded row in place without reordering")
    func competingBidUpdatesRowInPlace() async throws {
        let (server, repository) = await makeStack(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        await loadNextPage(viewModel)
        await loadNextPage(viewModel)
        let order = viewModel.loadedIDs
        #expect(order.count == 45)

        let competing = try #require(server.simulateCompetingBid())
        await waitUntil { viewModel.vehicles.contains(competing) }

        let row = try #require(viewModel.vehicles.first { $0.id == competing.id })
        #expect(row.currentBid == competing.currentBid)
        #expect(row.bidCount == 1)
        // Rows keep their page order; only the changed row is replaced.
        #expect(viewModel.loadedIDs == order)
        #expect(viewModel.totalCount == 45)
        #expect(viewModel.pageStatus == .complete)
    }

    @Test("LIVE-1: updates for lots that aren't loaded leave the rows unchanged")
    func updateForUnloadedLotIgnored() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        let rows = viewModel.vehicles
        let unloaded = try #require(fleet.map(\.id).first { !viewModel.loadedIDs.contains($0) })
        var updates = repository.inventoryUpdates().makeAsyncIterator()

        _ = try await repository.placeBid(20_000, on: unloaded).get()
        _ = await updates.next()
        await waitUntil { false }

        #expect(viewModel.vehicles == rows)
    }

    @Test("LIVE-3: the row flags you as outbid after your bid is beaten by a competing bid")
    func outbidSurfacesInRow() async throws {
        let lot = VehicleModel.fixture(buyNowPrice: 90_000, currentBid: 20_000, bidCount: 5)
        let (server, repository) = await makeStack([lot])
        let viewModel = await makeStartedViewModel(repository: repository)

        _ = try await repository.placeBid(20_500, on: lot.id).get()
        await waitUntil { viewModel.vehicles.first?.isYouHighBidder == true }
        #expect(viewModel.vehicles.first?.isYouOutbid == false)

        // The only lot is active, so the market must bid on it.
        try #require(server.simulateCompetingBid() != nil)
        await waitUntil { viewModel.vehicles.first?.isYouOutbid == true }

        let row = try #require(viewModel.vehicles.first)
        #expect(row.isYouOutbid)
        #expect(!row.isYouHighBidder)
        #expect(row.currentBid == 21_000)
    }

    @Test("LIVE-1 / BID-6: rows catch up on changes made while the screen wasn't subscribed")
    func resubscribeCatchesUp() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = InventoryViewModel(repository: repository)
        let loadStates = Task { await viewModel.observeLoadState() }
        defer { loadStates.cancel() }
        await waitUntil { viewModel.isInventoryLoaded }
        await settle(viewModel)
        let id = try #require(viewModel.loadedIDs.first)

        _ = try await repository.placeBid(15_000, on: id).get()
        #expect(viewModel.vehicles.first?.currentBid == nil)

        let changes = Task { await viewModel.observeInventoryChanges() }
        defer { changes.cancel() }
        await waitUntil { viewModel.vehicles.first?.currentBid != nil }

        #expect(viewModel.vehicles.first?.currentBid == 15_000)
    }

}
