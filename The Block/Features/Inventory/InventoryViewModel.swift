//
//  InventoryViewModel.swift
//  The Block
//
//  Inventory screen state: search debounce, filters, sort, cursor paging,
//  and live row updates from the vehicle repository.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Observation
import OSLog

/// Inventory screen state: search, filters, sort, and cursor-paged results (spec LIST-*).
///
/// Owns the loaded rows in page order. The view's `.task` runs `observeLoadState()`,
/// `observeInventoryChanges()`, and `observeStatusChanges()`, so the first page starts when the
/// feed connects, a loaded row is replaced in place whenever its lot changes, and a status filter
/// is re-applied when a lot starts or ends (spec LIVE-1, LIST-3, LIST-7, BID-6, TIME-4).
@Observable
final class InventoryViewModel {

    /// What the screen shows as a whole (spec DATA-3, UX-5).
    enum Content: Equatable {
        /// The feed is connecting, or page one is still on its way.
        case loading
        /// The feed failed to load; retry reconnects it.
        case loadFailed(message: String)
        /// The feed loaded but page one failed; retry requests the page again.
        case firstPageFailed
        /// Page one arrived; the list (or empty state when nothing matches) is shown.
        case results
    }

    /// State of the paging pipeline, drives the last list row (spec LIST-7).
    enum PageStatus: Equatable {
        /// More pages may follow; none is loading.
        case idle
        /// A page request is in flight.
        case loading
        /// The last page request failed.
        case failed
        /// The last page has loaded.
        case complete
    }

    /// One active filter, shown as a removable chip (spec LIST-3).
    enum FilterChip: Hashable, Identifiable {
        case status(StatusFilter)
        case bodyStyle(BodyStyle)
        case fuelType(FuelType)
        case province(String)
        case buyNowOnly

        var id: Self { self }
    }

    /// Text in the search field; applied to `query` after a short debounce (spec LIST-2).
    var searchText = "" {
        didSet { scheduleSearch() }
    }

    /// Search, filters, and sort. Any change restarts paging from page one.
    var query = InventoryQuery() {
        didSet {
            if query != oldValue { restart() }
        }
    }

    /// Loaded rows in page order; kept current by `observeInventoryChanges()`.
    private(set) var vehicles: [VehicleModel] = []
    /// Latest feed state from `observeLoadState()`.
    private(set) var loadState: LoadState = .idle
    /// Provinces present in the inventory, alphabetically, for the province filter.
    private(set) var availableProvinces: [String] = []
    /// Number of lots matching the query, from the latest page; `nil` until page one arrives (spec LIST-6).
    private(set) var totalCount: Int?
    /// Paging pipeline state; drives the last list row.
    private(set) var pageStatus: PageStatus = .idle

    /// The in-flight page request; awaited by pull-to-refresh and tests.
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    @ObservationIgnored private let repository: VehicleRepositoryProtocol
    /// Pending debounce that applies `searchText` to `query`.
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Cursor from the latest page; `nil` before page one and after the last page.
    @ObservationIgnored private var nextCursor: PageCursor?
    /// When page one's status-filtered results go out of date because a lot starts or ends;
    /// `nil` without a status filter (spec LIST-3, TIME-4).
    @ObservationIgnored private var statusChangeAt: Date?
    /// How often `observeStatusChanges()` checks the clock.
    @ObservationIgnored private let clockTick: Duration
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "InventoryViewModel")

    /// - Parameters:
    ///   - repository: Shared repository; rows, pages, and "now" are always read from it.
    ///   - clockTick: How often a status filter is re-checked against the clock; shorter in tests.
    init(repository: VehicleRepositoryProtocol, clockTick: Duration = .seconds(1)) {
        self.repository = repository
        self.clockTick = clockTick
    }

    // MARK: - Derived state

    /// IDs of the loaded rows, in page order.
    var loadedIDs: [VehicleModel.ID] {
        vehicles.map(\.id)
    }

    /// Whether the feed has delivered its snapshot.
    var isInventoryLoaded: Bool {
        loadState == .loaded
    }

    /// The repository's current time, for status text outside a `TimelineView`.
    var now: Date {
        repository.now
    }

    /// Active filters in a stable display order (status, body, fuel, province, Buy Now).
    var activeFilters: [FilterChip] {
        var chips: [FilterChip] = []
        chips += StatusFilter.allCases.filter(query.statuses.contains).map(FilterChip.status)
        chips += BodyStyle.allCases.filter(query.bodyStyles.contains).map(FilterChip.bodyStyle)
        chips += FuelType.allCases.filter(query.fuelTypes.contains).map(FilterChip.fuelType)
        chips += query.provinces.sorted().map(FilterChip.province)
        if query.buyNowOnly { chips.append(.buyNowOnly) }
        return chips
    }

    /// Whether any filter is on; drives the chip row and the filter button icon.
    var hasActiveFilters: Bool {
        !activeFilters.isEmpty
    }

    /// Screen-level state: full-screen loading/error until the first page arrives (spec UX-5).
    var content: Content {
        switch loadState {
        case .idle, .loading:
            return .loading
        case .failed(let message):
            return .loadFailed(message: message)
        case .loaded:
            guard totalCount == nil else { return .results }
            return pageStatus == .failed ? .firstPageFailed : .loading
        }
    }

    // MARK: - Live data

    /// Follows the feed's load state until cancelled (spec LIVE-1, LIVE-4, UX-5).
    ///
    /// Each time the state becomes `.loaded` (first connect or a reconnect after a failure),
    /// collects the provinces for the filter and restarts paging from page one. Repeated
    /// `.loaded` values, e.g. after re-subscribing, keep the rows already loaded.
    /// Run from the view's `.task`, so it stops when the screen goes away.
    func observeLoadState() async {
        for await state in repository.loadStateUpdates() {
            let wasLoaded = isInventoryLoaded
            loadState = state
            guard state == .loaded, !wasLoaded else { continue }
            availableProvinces = Set(repository.vehicles.map(\.province)).sorted()
            restart()
        }
    }

    /// Replaces loaded rows in place whenever their lot changes, until cancelled (spec LIVE-1, LIVE-3, BID-6).
    ///
    /// Rows keep their page order and the result count stays from the last page, so the list
    /// doesn't jump while you watch; changes to lots that aren't loaded are ignored. On start it
    /// refreshes loaded rows from the repository to pick up changes missed while unsubscribed.
    /// Run from the view's `.task`, so it stops when the screen goes away.
    func observeInventoryChanges() async {
        let updates = repository.inventoryUpdates()
        // Catch up on changes made while nobody was listening (e.g. a bid placed on the detail screen).
        vehicles = vehicles.map { repository.vehicle(id: $0.id) ?? $0 }
        for await vehicle in updates {
            replaceRow(with: vehicle)
        }
    }

    /// Restarts page one whenever a lot starts or ends while a status filter is on, until cancelled
    /// (spec LIST-3, TIME-4).
    ///
    /// Status filters depend on the time, so their results and count change without any feed
    /// event. Checks the repository's clock every `clockTick` against the moment page one went
    /// out of date. Loaded rows stay visible during the restart. Run from the view's `.task`.
    func observeStatusChanges() async {
        while (try? await Task.sleep(for: clockTick)) != nil {
            guard let statusChangeAt, repository.now >= statusChangeAt else { continue }
            restart()
        }
    }

    // MARK: - Paging

    /// Cancels any in-flight request and loads page one for the current query.
    ///
    /// Already loaded rows stay visible until the new page replaces them, so filter
    /// changes and pull-to-refresh don't flash an empty list.
    func restart() {
        nextCursor = nil
        // Set again when page one arrives, so a failed page one isn't retried on every tick.
        statusChangeAt = nil
        startLoading(after: nil)
    }

    /// Loads the next page when `id` is within the final few rows (spec LIST-7).
    func loadNextPageIfNeeded(currentID id: VehicleModel.ID) {
        guard let index = vehicles.firstIndex(where: { $0.id == id }),
              index >= max(vehicles.count - Constants.prefetchDistance, 0),
              let nextCursor,
              pageStatus == .idle else { return }
        startLoading(after: nextCursor)
    }

    /// Retries the page that failed: page one, or the next page after the loaded rows.
    func retryPage() {
        guard totalCount != nil, let nextCursor else {
            restart()
            return
        }
        startLoading(after: nextCursor)
    }

    /// Pull-to-refresh: restarts from page one and waits until it has loaded.
    func refresh() async {
        restart()
        await loadTask?.value
    }

    /// Reconnects the feed after a failed load (spec DATA-3, LIVE-4).
    ///
    /// `observeLoadState()` sees the new `.loaded` state and loads page one.
    func retryLoad() async {
        await repository.load()
    }

    // MARK: - Filters

    /// Whether `chip`'s filter is currently on.
    func isSelected(_ chip: FilterChip) -> Bool {
        switch chip {
        case .status(let status): query.statuses.contains(status)
        case .bodyStyle(let style): query.bodyStyles.contains(style)
        case .fuelType(let fuel): query.fuelTypes.contains(fuel)
        case .province(let province): query.provinces.contains(province)
        case .buyNowOnly: query.buyNowOnly
        }
    }

    /// Turns one filter on or off; the query change restarts paging.
    func setFilter(_ chip: FilterChip, isOn: Bool) {
        switch chip {
        case .status(let status): query.statuses.set(status, isOn: isOn)
        case .bodyStyle(let style): query.bodyStyles.set(style, isOn: isOn)
        case .fuelType(let fuel): query.fuelTypes.set(fuel, isOn: isOn)
        case .province(let province): query.provinces.set(province, isOn: isOn)
        case .buyNowOnly: query.buyNowOnly = isOn
        }
    }

    /// Removes one active filter (tapping its chip).
    func remove(_ chip: FilterChip) {
        setFilter(chip, isOn: false)
    }

    /// Clears every filter, keeping the search text and sort order (spec LIST-3).
    func clearFilters() {
        query = InventoryQuery(searchText: query.searchText, sort: query.sort)
    }

    /// Clears the search text and every filter at once, keeping the sort (spec LIST-5).
    func clearSearchAndFilters() {
        searchText = ""
        searchTask?.cancel()
        query = InventoryQuery(sort: query.sort)
    }

    // MARK: - Private

    /// Swaps in the new copy of a loaded lot at its current position; unknown lots are ignored.
    private func replaceRow(with vehicle: VehicleModel) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        vehicles[index] = vehicle
    }

    /// Applies `searchText` to `query` once typing pauses for `Constants.searchDebounce` (spec LIST-2).
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Constants.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            query.searchText = searchText.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Cancels the in-flight request and starts loading the page after `cursor` (page one when `nil`).
    private func startLoading(after cursor: PageCursor?) {
        loadTask?.cancel()
        pageStatus = .loading
        loadTask = Task { [weak self] in
            await self?.fetchPage(after: cursor)
        }
    }

    /// Fetches one page and applies it, unless the request was cancelled by a newer one.
    ///
    /// A stale cursor restarts from page one without showing an error; any other failure
    /// becomes the failed page state (full-screen for page one, inline row afterwards).
    private func fetchPage(after cursor: PageCursor?) async {
        do {
            let page = try await repository.fetchPage(query, after: cursor, limit: Constants.pageSize)
            guard !Task.isCancelled else { return }
            apply(page, isFirstPage: cursor == nil)
        } catch PagingError.staleCursor {
            guard !Task.isCancelled else { return }
            logger.info("[InventoryViewModel] stale cursor, restarting from page one")
            restart()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            logger.error("[InventoryViewModel] page load failed: \(String(describing: error), privacy: .public)")
            if cursor == nil {
                vehicles = []
                totalCount = nil
            }
            pageStatus = .failed
        }
    }

    /// Replaces rows with page one, or appends a later page's rows that aren't loaded yet.
    private func apply(_ page: InventoryPage, isFirstPage: Bool) {
        if isFirstPage {
            vehicles = page.vehicles
            statusChangeAt = query.nextStatusChange(in: repository.vehicles, after: repository.now)
        } else {
            let known = Set(loadedIDs)
            vehicles += page.vehicles.filter { !known.contains($0.id) }
        }
        nextCursor = page.nextCursor
        totalCount = page.totalCount
        pageStatus = page.nextCursor == nil ? .complete : .idle
    }

}

private extension Set {

    /// Inserts `member` when `isOn`, removes it otherwise.
    mutating func set(_ member: Element, isOn: Bool) {
        if isOn {
            insert(member)
        } else {
            remove(member)
        }
    }

}

/// Paging and search tuning.
private enum Constants {
    static let pageSize = 20
    static let prefetchDistance = 5
    static let searchDebounce: Duration = .milliseconds(300)
}
