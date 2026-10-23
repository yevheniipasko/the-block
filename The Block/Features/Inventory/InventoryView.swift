import SwiftUI

/// Inventory list with search, filters, sort, and cursor paging (spec LIST-*, UX-*).
///
/// Selecting a row writes its ID into `selection`, which the router turns into navigation.
struct InventoryView: View {

    @Bindable var viewModel: InventoryViewModel
    @Binding var selection: VehicleModel.ID?

    @State private var isFilterSheetPresented = false
    @State private var countdownPausedAt: Date?

    var body: some View {
        content
            .navigationTitle(Localizable.title)
            .searchable(text: $viewModel.searchText, prompt: Localizable.searchPrompt)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    sortMenu
                    filterButton
                }
            }
            .sheet(isPresented: $isFilterSheetPresented) {
                InventoryFilterSheet(viewModel: viewModel)
            }
            .task { await viewModel.observeLoadState() }
            .task { await viewModel.observeInventoryChanges() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.content {
        case .loading:
            LoadingStateView(message: Localizable.loading)
        case .loadFailed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.retryLoad() }
            }
        case .firstPageFailed:
            ErrorStateView(message: Localizable.pageFailed, retry: viewModel.retryPage)
        case .results:
            if viewModel.totalCount == 0 {
                emptyState
            } else {
                resultsList
            }
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        List(selection: $selection) {
            InventoryResultsHeader(viewModel: viewModel)
            ForEach(viewModel.vehicles) { vehicle in
                VehicleCardView(
                    vehicle: vehicle,
                    now: viewModel.now,
                    countdownPausedAt: countdownPausedAt
                )
                    .tag(vehicle.id)
                    .listRowInsets(Constants.cardInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("list.row.\(vehicle.lot)")
                    .onAppear { viewModel.loadNextPageIfNeeded(currentID: vehicle.id) }
            }
            pageStatusRow
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await viewModel.refresh() }
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .idle, newPhase != .idle {
                countdownPausedAt = .now
            } else if newPhase == .idle {
                countdownPausedAt = nil
            }
        }
    }

    @ViewBuilder private var pageStatusRow: some View {
        switch viewModel.pageStatus {
        case .loading:
            PageStatusRow(status: .loading)
        case .failed:
            PageStatusRow(status: .failed(retry: viewModel.retryPage))
        case .idle, .complete:
            EmptyView()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Localizable.emptyTitle, systemImage: "magnifyingglass")
                .accessibilityIdentifier("list.emptyState")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button(Localizable.clear, action: viewModel.clearSearchAndFilters)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("list.emptyState.clearButton")
        }
    }

    /// Names what produced no results, e.g. `Nothing matches “bronco” · Live · SUV.`
    private var emptyDescription: String {
        var terms: [String] = []
        let search = viewModel.query.searchText
        if !search.isEmpty {
            terms.append("“\(search)”")
        }
        terms += viewModel.activeFilters.map { InventoryLabels.title(for: $0) }
        guard !terms.isEmpty else { return Localizable.emptyNoCriteria }
        return Localizable.emptyDescription(terms.joined(separator: " · "))
    }

    // MARK: - Toolbar

    private var sortMenu: some View {
        Menu {
            Picker(Localizable.sortBy, selection: $viewModel.query.sort) {
                ForEach(InventorySort.allCases, id: \.self) { sort in
                    Text(InventoryLabels.title(for: sort)).tag(sort)
                }
            }
        } label: {
            Label(Localizable.sort, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("list.sortMenu")
        .accessibilityValue(InventoryLabels.title(for: viewModel.query.sort))
    }

    private var filterButton: some View {
        Button {
            isFilterSheetPresented = true
        } label: {
            Label(
                Localizable.filters,
                systemImage: viewModel.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityIdentifier("list.filterButton")
        .accessibilityValue(Localizable.activeFilterCount(viewModel.activeFilters.count))
    }

}

/// Result count plus removable chips for the active filters (spec LIST-3, LIST-6).
private struct InventoryResultsHeader: View {

    let viewModel: InventoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Label(Localizable.liveAuction, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Spacer(minLength: Spacing.small)
                Text(InventoryLabels.resultCount(viewModel.totalCount ?? 0))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("list.resultCount")
            }
            Text(Localizable.headline)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(Localizable.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.hasActiveFilters {
                chips
            }
        }
        .padding(Spacing.large)
        .background(
            Color.accentColor.opacity(Constants.headerTintOpacity),
            in: .rect(cornerRadius: CornerRadius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Color.accentColor.opacity(Constants.headerBorderOpacity))
        }
        .listRowInsets(Constants.headerInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.small) {
                ForEach(viewModel.activeFilters) { chip in
                    Button {
                        viewModel.remove(chip)
                    } label: {
                        Label(InventoryLabels.title(for: chip), systemImage: "xmark")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, Spacing.medium)
                            .padding(.vertical, Spacing.xSmall)
                            .background(Color.accentColor.opacity(Constants.chipOpacity), in: Capsule())
                    }
                    .accessibilityLabel(Localizable.removeFilter(InventoryLabels.title(for: chip)))
                    .accessibilityIdentifier("list.filterChip.\(InventoryLabels.title(for: chip))")
                }
                Button(Localizable.clearAll, action: viewModel.clearFilters)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("list.clearFiltersButton")
            }
        }
        .buttonStyle(.borderless)
    }

}

/// Title first, icon after it, for removable chips.
private struct TrailingIconLabelStyle: LabelStyle {

    /// Lays out the title followed by a small icon.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xSmall) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }

}

private enum Constants {
    static let chipOpacity = 0.15
    static let headerTintOpacity = 0.09
    static let headerBorderOpacity = 0.2
    static let headerInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    static let cardInsets = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
}

private enum Localizable {
    static let title = "The Block"
    static let liveAuction = "LIVE VEHICLE AUCTION"
    static let headline = "Inventory on the block"
    static let subtitle = "Follow live bids, watch the clock, and open any lot for full details."
    static let searchPrompt = "Make, model, year, lot, VIN, dealer"
    static let loading = "Loading inventory…"
    static let pageFailed = "We couldn't load the vehicles. Please try again."
    static let emptyTitle = "No matching vehicles"
    static let emptyNoCriteria = "There are no vehicles in this auction right now."
    static let clear = "Clear search and filters"
    static let clearAll = "Clear all"
    static let sort = "Sort"
    static let sortBy = "Sort by"
    static let filters = "Filters"
    static func emptyDescription(_ terms: String) -> String {
        "Nothing matches \(terms). Try a different search or clear the filters."
    }
    static func activeFilterCount(_ count: Int) -> String {
        count == 0 ? "None active" : "\(count) active"
    }
    static func removeFilter(_ name: String) -> String { "Remove filter \(name)" }
}
