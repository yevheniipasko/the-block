import Foundation
import Observation
import OSLog

/// Inventory screen state: search, filters, sort, and cursor-paged results (spec LIST-*).
///
/// Owns the loaded rows in page order. The view's `.task` runs `observeLoadState()` and
/// `observeInventoryChanges()`, so the first page starts when the feed connects and a loaded row
/// is replaced in place whenever its lot changes (spec LIVE-1, LIST-7, BID-6).
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

    /// Loaded rows in page order; kept current by `observeInventoryChanges()`.
    private(set) var vehicles: [VehicleModel] = []
    /// Latest feed state from `observeLoadState()`.
    private(set) var loadState: LoadState = .idle
    /// Provinces present in the inventory, alphabetically, for the province filter.
    private(set) var availableProvinces: [String] = []
    private(set) var totalCount: Int?
    private(set) var pageStatus: PageStatus = .idle

    /// The in-flight page request; awaited by pull-to-refresh and tests.
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    @ObservationIgnored private let repository: VehicleRepositoryProtocol
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var nextCursor: PageCursor?
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "InventoryViewModel")

    /// - Parameter repository: Shared repository; rows and pages are always read from it.
    init(repository: VehicleRepositoryProtocol) {
        self.repository = repository
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

    func observeLoadState() async {
        for await state in repository.loadStateUpdates() {
            let wasLoaded = isInventoryLoaded
            loadState = state
            guard state == .loaded, !wasLoaded else { continue }
            availableProvinces = Set(repository.vehicles.map(\.province)).sorted()
            restart()
        }
    }

    func observeInventoryChanges() async {
        let updates = repository.inventoryUpdates()
        // Catch up on changes made while nobody was listening (e.g. a bid placed on the detail screen).
        vehicles = vehicles.map { repository.vehicle(id: $0.id) ?? $0 }
        for await vehicle in updates {
            replaceRow(with: vehicle)
        }
    }

    // MARK: - Paging

    /// Cancels any in-flight request and loads page one for the current query.
    ///
    /// Already loaded rows stay visible until the new page replaces them, so filter
    /// changes and pull-to-refresh don't flash an empty list.
    func restart() {
        nextCursor = nil
        startLoading(after: nil)
    }

    /// Loads the next page when `id` is the last loaded row (spec LIST-7).
    func loadNextPageIfNeeded(currentID id: VehicleModel.ID) {
        guard id == vehicles.last?.id, let nextCursor, pageStatus == .idle else { return }
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

    private func apply(_ page: InventoryPage, isFirstPage: Bool) {
        if isFirstPage {
            vehicles = page.vehicles
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

private enum Constants {
    static let pageSize = 20
    static let searchDebounce: Duration = .milliseconds(300)
}
