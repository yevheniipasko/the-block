//
//  InventoryViewModelTests.swift
//  The Block
//
//  Tests for InventoryViewModel paging, query restarts, page failures and retry, filter chips,
//  and search debounce (LIST-2…LIST-7, BID-6, UX-5).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Real repository whose page requests can be made to fail on demand.
@MainActor
private final class FlakyPageRepository: VehicleRepositoryProtocol {

    let base: VehicleRepository
    /// When `true`, `fetchPage` throws instead of reaching the base repository.
    var failPages = false

    /// Wraps `base`, forwarding everything to it.
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

    /// Throws `StubError` while `failPages` is set; otherwise forwards to the base repository.
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

/// Inventory ViewModel paging, query restarts, page failures, filter chips, and search.
@MainActor
struct InventoryViewModelTests {

    private let fleet = inventoryFleet
    private let observers = InventoryObservers()

    /// Loaded repository on a stub server with a fixed clock.
    private func makeRepository(_ vehicles: [VehicleModel]) async -> VehicleRepository {
        await makeInventoryStack(vehicles, clock: FixedClock(now: TestDates.reference)).repository
    }

    /// Subscribed ViewModel with page one loaded, sorted by price.
    private func makeStartedViewModel(repository: VehicleRepositoryProtocol) async -> InventoryViewModel {
        await makeStartedInventory(repository: repository, observers: observers)
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

    @Test("LIST-7: a row far from the page boundary does not trigger the next page")
    func nextPageNotTriggeredEarly() async throws {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        viewModel.loadNextPageIfNeeded(currentID: try #require(viewModel.loadedIDs.first))
        await settle(viewModel)

        #expect(viewModel.loadedIDs.count == 20)
    }

    @Test("LIST-7: nearing the page boundary prefetches the next page")
    func nextPagePrefetchesNearBoundary() async {
        let repository = await makeRepository(fleet)
        let viewModel = await makeStartedViewModel(repository: repository)

        viewModel.loadNextPageIfNeeded(currentID: viewModel.loadedIDs[15])
        await settle(viewModel)

        #expect(viewModel.loadedIDs.count == 40)
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
        observers.start(viewModel)
        await waitUntil { viewModel.isInventoryLoaded }
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
        await waitUntil { viewModel.vehicles.first?.bidCount == 1 }

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
        let viewModel = await makeStartedViewModel(repository: repository)

        #expect(viewModel.availableProvinces == ["Ontario"])
    }

}
