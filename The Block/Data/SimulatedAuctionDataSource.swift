//
//  SimulatedAuctionDataSource.swift
//  The Block
//
//  In-process fake auction server: live vehicle feed, bid / Buy Now endpoints,
//  and a simulated market placing competing bids.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import OSLog

/// In-process stand-in for an auction server: a socket-like feed plus bid / Buy Now endpoints
/// (spec LIVE-1, LIVE-2).
///
/// Holds the authoritative lot state. The first snapshot comes from the bundled JSON with auction
/// starts normalized around `clock.now` (spec TIME-1). While anyone listens, a simulated market
/// places competing bids on active lots, so data changes without the buyer doing anything.
final class SimulatedAuctionDataSource: VehicleDataSourceProtocol {

    /// How the simulated market behaves; `nil` disables it (tests).
    struct Market: Sendable {
        /// Pause between competing bids.
        let interval: Duration
        /// Chance (0…1) that a competing bid targets a lot where the buyer is currently winning.
        let targetsYourLotsProbability: Double
    }

    private let loadSnapshot: () throws -> [VehicleModel]
    private let clock: AuctionClockProtocol
    private let latency: Duration
    private let market: Market?
    private let seedsDemoPositions: Bool
    private var generator: any RandomNumberGenerator
    private let logger = Logger(subsystem: "TheBlock", category: "SimulatedAuctionDataSource")

    /// Authoritative lot state; `nil` until the first snapshot loads.
    private var vehicles: [VehicleModel]?
    /// Open feed connections, keyed so each can be removed when it terminates.
    private var subscribers: [UUID: AsyncThrowingStream<VehicleFeedEvent, Error>.Continuation] = [:]
    /// Running market loop; only alive while at least one subscriber listens.
    private var marketTask: Task<Void, Never>?

    /// - Parameters:
    ///   - loadSnapshot: Produces the initial inventory (the bundled JSON in the app).
    ///   - clock: Source of "now" for normalization and rule checks.
    ///   - latency: Simulated round trip for `placeBid` / `buyNow`; `.zero` in tests.
    ///   - market: Competing-bid simulation, or `nil` for none.
    ///   - generator: Randomness for the market; seeded in tests.
    ///   - seedsDemoPositions: Start with one leading and one outbid position (`DemoSeed`, spec MYBIDS-7).
    init(
        loadSnapshot: @escaping () throws -> [VehicleModel],
        clock: AuctionClockProtocol,
        latency: Duration,
        market: Market?,
        generator: any RandomNumberGenerator,
        seedsDemoPositions: Bool = false
    ) {
        self.loadSnapshot = loadSnapshot
        self.clock = clock
        self.latency = latency
        self.market = market
        self.generator = generator
        self.seedsDemoPositions = seedsDemoPositions
    }

    func vehicleFeed() -> AsyncThrowingStream<VehicleFeedEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<VehicleFeedEvent, Error>.makeStream()
        do {
            continuation.yield(.snapshot(try snapshot()))
        } catch {
            logger.error("[SimulatedAuctionDataSource] snapshot failed: \(String(describing: error), privacy: .public)")
            continuation.finish(throwing: error)
            return stream
        }
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [self] in self?.unsubscribe(id) }
        }
        startMarketIfNeeded()
        return stream
    }

    func placeBid(_ amount: Int, on id: VehicleModel.ID) async throws -> VehicleModel {
        await simulateRoundTrip()
        var vehicle = try currentVehicle(id)
        if case .failure(let rejection) = BiddingRules.validateBid(amount, on: vehicle, at: clock.now) {
            throw rejection
        }
        vehicle.currentBid = amount
        vehicle.bidCount += 1
        vehicle.yourBid = amount
        publish(vehicle)
        return vehicle
    }

    func buyNow(_ id: VehicleModel.ID) async throws -> VehicleModel {
        await simulateRoundTrip()
        var vehicle = try currentVehicle(id)
        guard BiddingRules.canBuyNow(vehicle, at: clock.now), let price = vehicle.buyNowPrice else {
            throw BidRejection.buyNowUnavailable
        }
        vehicle.yourPurchasePrice = price
        publish(vehicle)
        return vehicle
    }

    /// Places one competing bid from another buyer and pushes it to the feed (spec LIVE-2).
    ///
    /// Picks an active lot that can take the next minimum bid below its Buy Now price, preferring
    /// lots the buyer is winning with `market.targetsYourLotsProbability`.
    /// - Returns: The updated lot, or `nil` when no lot can take a bid.
    @discardableResult
    func simulateCompetingBid() -> VehicleModel? {
        guard let vehicles else { return nil }
        let now = clock.now
        let candidates = vehicles.filter { BiddingRules.canTakeAnotherBid($0, at: now) }
        let yours = candidates.filter(\.isYouHighBidder)
        let probability = market?.targetsYourLotsProbability ?? 0
        let pool = !yours.isEmpty && Double.random(in: 0..<1, using: &generator) < probability ? yours : candidates
        guard var vehicle = pool.randomElement(using: &generator) else { return nil }
        vehicle.currentBid = BiddingRules.minimumNextBid(for: vehicle)
        vehicle.bidCount += 1
        publish(vehicle)
        return vehicle
    }

    // MARK: - Private

    /// Loads and normalizes the inventory once; a failed load is retried on the next connection.
    private func snapshot() throws -> [VehicleModel] {
        if let vehicles {
            return vehicles
        }
        let raw = try loadSnapshot()
        let schedule = AuctionSchedule(datasetStarts: raw.map(\.auctionStart), launchDate: clock.now)
        let normalized = raw.map { vehicle in
            var copy = vehicle
            copy.auctionStart = schedule.normalized(vehicle.auctionStart)
            return copy
        }
        let snapshot = seedsDemoPositions ? DemoSeed.apply(to: normalized, now: clock.now) : normalized
        vehicles = snapshot
        return snapshot
    }

    /// Looks up the server's copy of a lot.
    ///
    /// - Throws: `BidRejection.vehicleNotFound` when the lot is unknown or the snapshot never loaded.
    private func currentVehicle(_ id: VehicleModel.ID) throws -> VehicleModel {
        guard let vehicle = vehicles?.first(where: { $0.id == id }) else {
            throw BidRejection.vehicleNotFound
        }
        return vehicle
    }

    /// Stores the new lot state and pushes it to every subscriber.
    private func publish(_ vehicle: VehicleModel) {
        guard let index = vehicles?.firstIndex(where: { $0.id == vehicle.id }) else { return }
        vehicles?[index] = vehicle
        for continuation in subscribers.values {
            continuation.yield(.updated(vehicle))
        }
    }

    /// Drops a closed connection and stops the market once nobody listens.
    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty {
            marketTask?.cancel()
            marketTask = nil
        }
    }

    /// Starts the competing-bid loop on the first connection, if a market is configured (spec LIVE-2).
    ///
    /// The loop holds the data source weakly and ends once it is cancelled or the data source is gone.
    private func startMarketIfNeeded() {
        guard let market, marketTask == nil else { return }
        marketTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: market.interval)
                guard !Task.isCancelled, let self else { return }
                self.simulateCompetingBid()
            }
        }
    }

    /// Waits for the configured latency to imitate a network request.
    private func simulateRoundTrip() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }

}
