import Foundation
import Observation
import OSLog

/// Inventory screen state: search, filters, sort, and cursor-paged results (spec LIST-*).
///
/// Stores only the loaded vehicle IDs, in page order, and reads each row live from the
/// repository so bids placed elsewhere show up without a reload (spec LIST-7, BID-6).
@Observable
final class InventoryViewModel {

    /// What the screen shows as a whole (spec DATA-3, UX-5).
    enum Content: Equatable {
        case loading
        case loadFailed(message: String)
        case firstPageFailed
        case results
    }

    /// State of the paging pipeline, drives the last list row (spec LIST-7).
    enum PageStatus: Equatable {
        case idle
        case loading
        case failed
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

    private(set) var loadedIDs: [VehicleModel.ID] = []
    private(set) var totalCount: Int?
    private(set) var pageStatus: PageStatus = .idle

    /// The in-flight page request; awaited by pull-to-refresh and tests.
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    @ObservationIgnored private let repository: VehicleRepositoryProtocol
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var nextCursor: PageCursor?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "InventoryViewModel")

    init(repository: VehicleRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Derived state

    /// Loaded rows, read live from the repository in page order.
    var vehicles: [VehicleModel] {
        loadedIDs.compactMap { repository.vehicle(id: $0) }
    }

    /// Whether the repository has finished its initial load.
    var isInventoryLoaded: Bool {
        repository.loadState == .loaded
    }

    /// The repository's current time, for status text outside a `TimelineView`.
    var now: Date {
        repository.now
    }

    /// Provinces present in the inventory, alphabetically, for the province filter.
    var availableProvinces: [String] {
        Set(repository.vehicles.map(\.province)).sorted()
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

    var hasActiveFilters: Bool {
        !activeFilters.isEmpty
    }

    /// Screen-level state: full-screen loading/error until the first page arrives (spec UX-5).
    var content: Content {
        switch repository.loadState {
        case .idle, .loading:
            return .loading
        case .failed(let message):
            return .loadFailed(message: message)
        case .loaded:
            guard totalCount == nil else { return .results }
            return pageStatus == .failed ? .firstPageFailed : .loading
        }
    }

    // MARK: - Paging

    /// Loads page one once the repository is ready; later calls do nothing.
    func startIfNeeded() {
        guard isInventoryLoaded, !hasStarted else { return }
        restart()
    }

    /// Cancels any in-flight request and loads page one for the current query.
    ///
    /// Already loaded rows stay visible until the new page replaces them, so filter
    /// changes and pull-to-refresh don't flash an empty list.
    func restart() {
        hasStarted = true
        nextCursor = nil
        startLoading(after: nil)
    }

    /// Loads the next page when `id` is the last loaded row (spec LIST-7).
    func loadNextPageIfNeeded(currentID id: VehicleModel.ID) {
        guard id == loadedIDs.last, let nextCursor, pageStatus == .idle else { return }
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

    /// Retries a failed repository load, then loads page one (spec DATA-3).
    func retryLoad() async {
        await repository.load()
        guard isInventoryLoaded else { return }
        restart()
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

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Constants.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            query.searchText = searchText.trimmingCharacters(in: .whitespaces)
        }
    }

    private func startLoading(after cursor: PageCursor?) {
        loadTask?.cancel()
        pageStatus = .loading
        loadTask = Task { [weak self] in
            await self?.fetchPage(after: cursor)
        }
    }

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
                loadedIDs = []
                totalCount = nil
            }
            pageStatus = .failed
        }
    }

    private func apply(_ page: InventoryPage, isFirstPage: Bool) {
        let ids = page.vehicles.map(\.id)
        if isFirstPage {
            loadedIDs = ids
        } else {
            let known = Set(loadedIDs)
            loadedIDs += ids.filter { !known.contains($0) }
        }
        nextCursor = page.nextCursor
        totalCount = page.totalCount
        pageStatus = page.nextCursor == nil ? .complete : .idle
    }

}

private extension Set {

    mutating func set(_ member: Element, isOn: Bool) {
        if isOn {
            insert(member)
        } else {
            remove(member)
        }
    }

}

private enum Constants {
    static let pageSize = 20
    static let searchDebounce: Duration = .milliseconds(300)
}
