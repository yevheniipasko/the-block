import Foundation
import Testing
@testable import The_Block

/// Real repository whose page requests can be made to fail on demand.
@MainActor
private final class FlakyPageRepository: VehicleRepositoryProtocol {

    let base: VehicleRepository
    var failPages = false

    init(base: VehicleRepository) {
        self.base = base
    }

    var loadState: LoadState { base.loadState }
    var vehicles: [VehicleModel] { base.vehicles }
    var now: Date { base.now }

    func load() async { await base.load() }

    func vehicle(id: VehicleModel.ID) -> VehicleModel? { base.vehicle(id: id) }

    func loadStateUpdates() -> AsyncStream<LoadState> { base.loadStateUpdates() }

    func vehicleUpdates(id: VehicleModel.ID) -> AsyncStream<VehicleModel> { base.vehicleUpdates(id: id) }

    func inventoryUpdates() -> AsyncStream<VehicleModel> { base.inventoryUpdates() }

    func fetchPage(_ query: InventoryQuery, after cursor: PageCursor?, limit: Int) async throws -> InventoryPage {
        if failPages { throw StubError() }
        return try await base.fetchPage(query, after: cursor, limit: limit)
    }

    func placeBid(_ amount: Int, on id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection> {
        await base.placeBid(amount, on: id)
    }

    func buyNow(_ id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection> {
        await base.buyNow(id)
    }

}

@MainActor
struct InventoryViewModelTests {

    /// 45 active lots with distinct prices (10_000, 10_100, …) and Buy Now prices.
    private let fleet: [VehicleModel] = (0..<45).map { index in
        .fixture(startingBid: 10_000 + index * 100, buyNowPrice: 50_000)
    }

    private func makeRepository(_ vehicles: [VehicleModel]) async -> VehicleRepository {
        let repository = VehicleRepository.stubbed(
            result: .success(vehicles),
            clock: FixedClock(now: TestDates.reference)
        )
        await repository.load()
        return repository
    }

    /// Fleet sorted by price so page order is deterministic.
    private func makeStartedViewModel(
        repository: VehicleRepositoryProtocol
    ) async -> InventoryViewModel {
        let viewModel = InventoryViewModel(repository: repository)
        viewModel.query.sort = .priceLowToHigh
        await settle(viewModel)
        return viewModel
    }

    /// Waits until no page request is in flight, following restarts.
    private func settle(_ viewModel: InventoryViewModel) async {
        while viewModel.pageStatus == .loading, let task = viewModel.loadTask {
            await task.value
        }
    }

    private func loadNextPage(_ viewModel: InventoryViewModel) async {
        guard let last = viewModel.loadedIDs.last else { return }
        viewModel.loadNextPageIfNeeded(currentID: last)
        await settle(viewModel)
    }

    @Test("DATA-3 / UX-5: screen shows loading until the repository and first page are ready")
    func loadingUntilFirstPage() async {
        let repository = VehicleRepository.stubbed(
            result: .success(fleet),
            clock: FixedClock(now: TestDates.reference)
        )
        let viewModel = InventoryViewModel(repository: repository)
        #expect(viewModel.content == .loading)

        viewModel.startIfNeeded()
        #expect(viewModel.loadTask == nil)

        await repository.load()
        #expect(viewModel.content == .loading)

        viewModel.startIfNeeded()
        await settle(viewModel)
        #expect(viewModel.content == .results)
    }

    @Test("DATA-3: a failed repository load shows an error, and retry loads page one")
    func repositoryFailureAndRetry() async {
        let repository = VehicleRepository.stubbed(
            result: .failure(StubError()),
            clock: FixedClock(now: TestDates.reference)
        )
        await repository.load()
        let viewModel = InventoryViewModel(repository: repository)

        guard case .loadFailed = viewModel.content else {
            Issue.record("Expected loadFailed, got \(viewModel.content)")
            return
        }
        await viewModel.retryLoad()
        await settle(viewModel)
        #expect(viewModel.pageStatus != .loading)
    }

    @Test("LIST-6 / LIST-7: first page loads 20 rows and the total count")
    func firstPage() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        #expect(viewModel.loadedIDs.count == 20)
        #expect(viewModel.totalCount == 45)
        #expect(viewModel.pageStatus == .idle)
        #expect(viewModel.vehicles.first?.startingBid == 10_000)
    }

    @Test("LIST-7: next pages append without duplicates and stop at the end")
    func nextPagesUntilEnd() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        await loadNextPage(viewModel)
        #expect(viewModel.loadedIDs.count == 40)

        await loadNextPage(viewModel)
        #expect(viewModel.loadedIDs.count == 45)
        #expect(Set(viewModel.loadedIDs).count == 45)
        #expect(viewModel.pageStatus == .complete)

        await loadNextPage(viewModel)
        #expect(viewModel.loadedIDs.count == 45)
    }

    @Test("LIST-7: only the last loaded row triggers the next page")
    func nextPageOnlyFromLastRow() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        viewModel.loadNextPageIfNeeded(currentID: try #require(viewModel.loadedIDs.first))
        await settle(viewModel)

        #expect(viewModel.loadedIDs.count == 20)
    }

    @Test("LIST-4 / LIST-7: changing the query restarts from page one")
    func queryChangeRestarts() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        await loadNextPage(viewModel)

        viewModel.query.sort = .priceHighToLow
        await settle(viewModel)

        #expect(viewModel.loadedIDs.count == 20)
        #expect(viewModel.vehicles.first?.startingBid == 14_400)
        #expect(viewModel.pageStatus == .idle)
    }

    @Test("LIST-7: a stale cursor silently restarts from page one")
    func staleCursorRestarts() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        viewModel.setFilter(.status(.active), isOn: true)
        await settle(viewModel)
        let cursorID = try #require(viewModel.loadedIDs.last)

        // Buying the cursor's lot ends its auction, so it no longer matches "Active".
        _ = try await repository.buyNow(cursorID).get()
        await loadNextPage(viewModel)

        #expect(viewModel.pageStatus == .idle)
        #expect(viewModel.loadedIDs.count == 20)
        #expect(!viewModel.loadedIDs.contains(cursorID))
        #expect(viewModel.totalCount == 44)
    }

    @Test("LIST-7 / UX-5: a failed next page shows an inline retry that resumes paging")
    func nextPageFailureAndRetry() async {
        let repository = FlakyPageRepository(base: await makeRepository(fleet))
        let viewModel = await makeStartedViewModel(repository: repository)

        repository.failPages = true
        await loadNextPage(viewModel)
        #expect(viewModel.pageStatus == .failed)
        #expect(viewModel.content == .results)
        #expect(viewModel.loadedIDs.count == 20)

        repository.failPages = false
        viewModel.retryPage()
        await settle(viewModel)
        #expect(viewModel.loadedIDs.count == 40)
        #expect(viewModel.pageStatus == .idle)
    }

    @Test("UX-5: a failed first page shows a full-screen error, and retry loads it")
    func firstPageFailureAndRetry() async {
        let repository = FlakyPageRepository(base: await makeRepository(fleet))
        repository.failPages = true
        let viewModel = InventoryViewModel(repository: repository)
        viewModel.startIfNeeded()
        await settle(viewModel)
        #expect(viewModel.content == .firstPageFailed)

        repository.failPages = false
        viewModel.retryPage()
        await settle(viewModel)
        #expect(viewModel.content == .results)
        #expect(viewModel.loadedIDs.count == 20)
    }

    @Test("BID-6 / LIST-7: a bid placed through the repository shows in the loaded row")
    func bidReflectedInRow() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        let id = try #require(viewModel.loadedIDs.first)

        _ = try await repository.placeBid(10_000, on: id).get()

        let row = try #require(viewModel.vehicles.first)
        #expect(row.id == id)
        #expect(row.currentBid == 10_000)
        #expect(row.bidCount == 1)
        #expect(row.isYouHighBidder)
    }

    @Test("LIST-3: active filters appear as chips; removing one updates the query")
    func filterChips() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        viewModel.setFilter(.province("Ontario"), isOn: true)
        viewModel.setFilter(.status(.active), isOn: true)
        viewModel.setFilter(.buyNowOnly, isOn: true)
        #expect(viewModel.activeFilters == [.status(.active), .province("Ontario"), .buyNowOnly])
        #expect(viewModel.isSelected(.province("Ontario")))

        viewModel.remove(.status(.active))
        #expect(viewModel.query.statuses.isEmpty)
        #expect(viewModel.activeFilters == [.province("Ontario"), .buyNowOnly])
        await settle(viewModel)
        #expect(viewModel.totalCount == 45)
    }

    @Test("LIST-3: clear all removes every filter but keeps search and sort")
    func clearAllFilters() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        viewModel.query.searchText = "bronco"
        viewModel.setFilter(.bodyStyle(.sedan), isOn: true)
        viewModel.setFilter(.fuelType(.electric), isOn: true)
        await settle(viewModel)
        #expect(viewModel.totalCount == 0)

        viewModel.clearFilters()
        await settle(viewModel)

        #expect(!viewModel.hasActiveFilters)
        #expect(viewModel.query.searchText == "bronco")
        #expect(viewModel.query.sort == .priceLowToHigh)
        #expect(viewModel.totalCount == 45)
    }

    @Test("LIST-5: clear in the empty state resets search and filters")
    func clearSearchAndFilters() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)
        viewModel.searchText = "tesla"
        viewModel.query.searchText = "tesla"
        viewModel.setFilter(.status(.ended), isOn: true)
        await settle(viewModel)
        #expect(viewModel.totalCount == 0)

        viewModel.clearSearchAndFilters()
        await settle(viewModel)

        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.query == InventoryQuery(sort: .priceLowToHigh))
        #expect(viewModel.totalCount == 45)
    }

    @Test("LIST-2: typed search is applied to the query after the debounce")
    func searchDebounce() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        viewModel.searchText = "  zzz "
        #expect(viewModel.query.searchText.isEmpty)

        for _ in 0..<50 where viewModel.query.searchText.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        await settle(viewModel)

        #expect(viewModel.query.searchText == "zzz")
        #expect(viewModel.totalCount == 0)
    }

    @Test("LIST-3: provinces offered by the filter are the distinct inventory provinces")
    func availableProvinces() async {
        let repository = await makeRepository(fleet)
        let viewModel = InventoryViewModel(repository: repository)

        #expect(viewModel.availableProvinces == ["Ontario"])
    }

}
