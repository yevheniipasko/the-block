import Foundation
import Testing
@testable import The_Block

@MainActor
struct OutbidAlertCenterTests {

    private let clock = FixedClock(now: TestDates.reference)

    /// Active at launch (every lot starts at the anchor), with bids; `yourBid` sets the buyer's position.
    private func lot(id: UUID = UUID(), yourBid: Int? = nil) -> VehicleModel {
        .fixture(id: id, auctionStart: Date(timeIntervalSince1970: 0), currentBid: 20_000, bidCount: 5,
                 yourBid: yourBid)
    }

    /// Server whose competing bids always land on a lot the buyer is winning when there is one,
    /// so each `simulateCompetingBid()` outbids a known lot.
    private func makeServer(_ vehicles: [VehicleModel]) -> SimulatedAuctionDataSource {
        SimulatedAuctionDataSource(
            loadSnapshot: { vehicles },
            clock: clock,
            latency: .zero,
            market: .init(interval: .seconds(3_600), targetsYourLotsProbability: 1),
            generator: SeededGenerator(seed: 7)
        )
    }

    private func makeCenter(
        _ vehicles: [VehicleModel],
        displayDuration: Duration = .seconds(60),
        loadFirst: Bool = true
    ) async -> Harness {
        let server = makeServer(vehicles)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        if loadFirst {
            await repository.load()
        }
        let center = OutbidAlertCenter(repository: repository, displayDuration: displayDuration)
        let task = Task { await center.observe() }
        if !loadFirst {
            await Task.yield()
            await repository.load()
        }
        // Let `observe()` see the load and subscribe before the test produces updates.
        for _ in 0..<Constants.subscribeYields {
            await Task.yield()
        }
        return Harness(server: server, repository: repository, center: center, task: task)
    }

    /// Waits (sleeping, never spinning) until `condition` holds or the timeout passes.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + Constants.timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: Constants.pollInterval)
        }
    }

    @Test("ALERT-1: going from winning to outbid raises one alert with the lot title and new bid")
    func winningToOutbidAlerts() async throws {
        let id = UUID()
        let harness = await makeCenter([lot(id: id, yourBid: 20_000)])
        let server = harness.server
        let center = harness.center
        let task = harness.task
        defer { task.cancel() }

        let outbid = try #require(server.simulateCompetingBid())
        try await waitUntil { center.current != nil }

        let alert = try #require(center.current)
        #expect(alert.lotID == id)
        #expect(alert.title == outbid.title)
        #expect(alert.currentBid == outbid.currentBid)
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test("ALERT-2: several outbids queue in order and dismiss shows the next one")
    func outbidsQueueInOrder() async throws {
        let harness = await makeCenter([lot(yourBid: 20_000), lot(yourBid: 20_000)])
        let server = harness.server
        let center = harness.center
        let task = harness.task
        defer { task.cancel() }

        let first = try #require(server.simulateCompetingBid())
        let second = try #require(server.simulateCompetingBid())
        #expect(first.id != second.id)
        try await waitUntil { center.current != nil }

        #expect(center.current?.lotID == first.id)
        center.dismiss()
        // The second update may still be in flight on the feed when the first is dismissed.
        try await waitUntil { center.current?.lotID == second.id }
        #expect(center.current?.lotID == second.id)
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test("ALERT-2: the banner dismisses itself after the display duration")
    func autoDismiss() async throws {
        let harness = await makeCenter(
            [lot(yourBid: 20_000)], displayDuration: .milliseconds(20)
        )
        let server = harness.server
        let center = harness.center
        let task = harness.task
        defer { task.cancel() }

        server.simulateCompetingBid()
        try await waitUntil { center.current != nil }
        #expect(center.current != nil)

        try await waitUntil { center.current == nil }
        #expect(center.current == nil)
    }

    @Test("ALERT-3: no alert for the lot whose bid sheet is open")
    func suppressedLotDoesNotAlert() async throws {
        let suppressedID = UUID()
        let otherID = UUID()
        let harness = await makeCenter(
            [lot(id: suppressedID, yourBid: 20_000), lot(id: otherID)]
        )
        let server = harness.server
        let repository = harness.repository
        let center = harness.center
        let task = harness.task
        defer { task.cancel() }
        center.suppressedLotID = suppressedID

        // The buyer only leads on the suppressed lot, so the market outbids it first.
        #expect(server.simulateCompetingBid()?.id == suppressedID)
        _ = try await repository.placeBid(20_500, on: otherID).get()
        #expect(server.simulateCompetingBid()?.id == otherID)
        try await waitUntil { center.current != nil }

        // Updates are handled in order, so the suppressed lot's change was seen before this one.
        #expect(center.current?.lotID == otherID)
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test("ALERT-1: lots already outbid when observing starts never alert")
    func alreadyOutbidLotsDoNotAlert() async throws {
        let outbidID = UUID()
        let otherID = UUID()
        // Observing starts before the load, so it seeds from the snapshot once the load finishes.
        let harness = await makeCenter(
            [lot(id: outbidID, yourBid: 19_500), lot(id: otherID)],
            loadFirst: false
        )
        let server = harness.server
        let repository = harness.repository
        let center = harness.center
        let task = harness.task
        defer { task.cancel() }

        _ = try await repository.placeBid(20_500, on: otherID).get()
        #expect(server.simulateCompetingBid()?.id == otherID)
        try await waitUntil { center.current != nil }

        #expect(center.current?.lotID == otherID)
        center.dismiss()
        #expect(center.current == nil)
    }

}

/// Everything a test needs: the fake server, the repository, the center, and its observing task.
@MainActor
private struct Harness {
    let server: SimulatedAuctionDataSource
    let repository: VehicleRepository
    let center: OutbidAlertCenter
    let task: Task<Void, Never>
}

private enum Constants {
    static let subscribeYields = 3
    static let timeout: Duration = .seconds(2)
    static let pollInterval: Duration = .milliseconds(5)
}
