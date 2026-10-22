import Foundation
import Observation

/// "My bids" screen state: every lot you bid on or bought, grouped by your position (spec MYBIDS-*).
///
/// One instance lives for the whole app (held by the router), so the toolbar's outbid badge stays
/// current while the screen is closed. `observe()` keeps the groups live from the repository feed
/// and a one-second clock tick (an auction ending changes your position without a feed event).
@Observable
final class MyBidsViewModel {

    /// Lots that share one position, in display order inside the group.
    struct Group: Identifiable, Equatable {
        let position: BidPosition
        let vehicles: [VehicleModel]

        var id: BidPosition { position }
    }

    /// Display order of the groups (spec MYBIDS-2).
    static let groupOrder: [BidPosition] = [.winning, .outbid, .won, .bought, .lost]

    /// Non-empty groups in `groupOrder` (spec MYBIDS-2).
    private(set) var groups: [Group] = []

    @ObservationIgnored private let repository: VehicleRepositoryProtocol
    @ObservationIgnored private let tickInterval: Duration

    /// Builds the groups from the repository's current vehicles.
    ///
    /// - Parameters:
    ///   - repository: Shared repository; its feed and clock drive every position.
    ///   - tickInterval: How often positions are re-evaluated against the clock.
    init(repository: VehicleRepositoryProtocol, tickInterval: Duration = .seconds(1)) {
        self.repository = repository
        self.tickInterval = tickInterval
        refreshPositions()
    }

    /// No bids or purchases yet: the screen shows its empty state (spec MYBIDS-5).
    var isEmpty: Bool {
        groups.isEmpty
    }

    /// Lots where someone else holds the high bid on a running auction (spec MYBIDS-6).
    var outbidCount: Int {
        groups.first { $0.position == .outbid }?.vehicles.count ?? 0
    }

    /// Keeps the groups live until the calling task is cancelled (spec MYBIDS-4).
    ///
    /// Each update is used as a "something changed" signal and the groups are rebuilt from the
    /// repository's current state: the update stream keeps only the newest values for a slow
    /// subscriber, so the 200-lot snapshot burst can drop individual lots. Subscribes before the
    /// first rebuild, so no change between the two is lost. A child task also rebuilds every
    /// `tickInterval`, because an auction ending moves a lot from Winning to Won (or Outbid to Lost)
    /// without any feed event.
    func observe() async {
        let updates = repository.inventoryUpdates()
        refreshPositions()
        let ticker = Task { [weak self] in await self?.tickUntilCancelled() }
        defer { ticker.cancel() }
        for await _ in updates {
            refreshPositions()
        }
    }

    /// Rebuilds the groups from the repository's latest vehicles at its current time.
    ///
    /// Only assigns when something changed, so the clock tick doesn't redraw the list every second.
    func refreshPositions() {
        let now = repository.now
        let byPosition = Dictionary(grouping: repository.vehicles) { $0.bidPosition(at: now) }
        let newGroups = Self.groupOrder.compactMap { position -> Group? in
            guard let vehicles = byPosition[position], !vehicles.isEmpty else { return nil }
            return Group(position: position, vehicles: vehicles.sorted { Self.displayOrder($0, $1) })
        }
        if newGroups != groups {
            groups = newGroups
        }
    }

    // MARK: - Private

    private func tickUntilCancelled() async {
        while (try? await Task.sleep(for: tickInterval)) != nil {
            refreshPositions()
        }
    }

    /// Ending soonest first; lot number breaks ties so the order is stable.
    private static func displayOrder(_ lhs: VehicleModel, _ rhs: VehicleModel) -> Bool {
        if lhs.auctionEnd != rhs.auctionEnd {
            return lhs.auctionEnd < rhs.auctionEnd
        }
        return lhs.lot < rhs.lot
    }

}
