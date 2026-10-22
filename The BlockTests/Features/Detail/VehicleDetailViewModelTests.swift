import Foundation
import Testing
@testable import The_Block

@MainActor
struct VehicleDetailViewModelTests {

    /// With fewer than 121 vehicles the latest dataset start is mapped to `launch`.
    private let launch = TestDates.reference
    private let datasetAnchor = Date(timeIntervalSince1970: 1_000_000)

    private func makeViewModel(_ vehicle: VehicleModel) async -> (VehicleDetailViewModel, VehicleRepository) {
        let stack = await makeStack(vehicle)
        return (stack.viewModel, stack.repository)
    }

    /// View model on a repository whose stub server is exposed, so tests can push competing bids.
    private func makeStack(_ vehicle: VehicleModel) async -> Stack {
        let clock = FixedClock(now: launch)
        let server = SimulatedAuctionDataSource.stub(result: .success([vehicle]), clock: clock)
        let repository = VehicleRepository(dataSource: server, clock: clock)
        await repository.load()
        return Stack(
            viewModel: VehicleDetailViewModel(vehicleID: vehicle.id, repository: repository),
            repository: repository,
            server: server
        )
    }

    /// Starts `observeVehicle()` like the view's `.task` and lets it subscribe before returning.
    private func startObserving(_ viewModel: VehicleDetailViewModel) async -> Task<Void, Never> {
        let task = Task { await viewModel.observeVehicle() }
        for _ in 0..<5 {
            await Task.yield()
        }
        return task
    }

    /// Yields a bounded number of times until `condition` holds; updates arrive on the main actor,
    /// so a busy-wait would never let them through.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<50 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - DETAIL-6 / TIME-4 action bar

    @Test("DETAIL-6: upcoming lot offers a bid from the minimum, no Buy Now")
    func upcomingOffersBidOnly() async {
        let (viewModel, _) = await makeViewModel(.fixture(startingBid: 12_000, buyNowPrice: 30_000))

        let state = viewModel.actionBar(at: launch.addingTimeInterval(-TestDates.hours(1)))

        #expect(state == .bidding(minimumBid: 12_000, buyNowPrice: nil))
    }

    @Test("DETAIL-6: active lot with a Buy Now price offers both actions")
    func activeWithBuyNow() async {
        let (viewModel, _) = await makeViewModel(.fixture(buyNowPrice: 30_000, currentBid: 23_000, bidCount: 14))

        #expect(viewModel.actionBar(at: launch) == .bidding(minimumBid: 24_000, buyNowPrice: 30_000))
    }

    @Test("DETAIL-6: active lot without a Buy Now price offers only a bid")
    func activeWithoutBuyNow() async {
        let (viewModel, _) = await makeViewModel(.fixture(startingBid: 8_000))

        #expect(viewModel.actionBar(at: launch) == .bidding(minimumBid: 8_000, buyNowPrice: nil))
    }

    @Test("DETAIL-6 / TIME-4: ended lot shows its outcome instead of actions")
    func endedShowsOutcome() async {
        let (viewModel, _) = await makeViewModel(.fixture(buyNowPrice: 30_000, currentBid: 20_000, bidCount: 3))

        let afterEnd = launch.addingTimeInterval(AuctionSchedule.duration + 1)

        #expect(viewModel.actionBar(at: afterEnd) == .ended(.sold))
    }

    @Test("TIME-4: actions flip as the lot moves from upcoming to active to ended")
    func actionsFlipOverTime() async {
        let (viewModel, _) = await makeViewModel(.fixture(buyNowPrice: 30_000))

        let upcoming = viewModel.actionBar(at: launch.addingTimeInterval(-1))
        let active = viewModel.actionBar(at: launch)
        let ended = viewModel.actionBar(at: launch.addingTimeInterval(AuctionSchedule.duration))

        #expect(upcoming == .bidding(minimumBid: 10_000, buyNowPrice: nil))
        #expect(active == .bidding(minimumBid: 10_000, buyNowPrice: 30_000))
        #expect(ended == .ended(.noSale))
    }

    @Test("DETAIL-6: missing vehicle has no action bar")
    func missingVehicle() async {
        let (_, repository) = await makeViewModel(.fixture())
        let viewModel = VehicleDetailViewModel(vehicleID: UUID(), repository: repository)

        #expect(viewModel.vehicle == nil)
        #expect(viewModel.actionBar(at: launch) == nil)
    }

    // MARK: - BID-6 / BID-10 live state

    @Test("BID-6: a bid placed through the repository shows on detail without a reload")
    func bidUpdatesDetail() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle)
        let observing = await startObserving(viewModel)
        defer { observing.cancel() }

        await repository.placeBid(24_000, on: vehicle.id)
        await settle { viewModel.vehicle?.currentBid == 24_000 }

        #expect(viewModel.vehicle?.currentBid == 24_000)
        #expect(viewModel.bidCountText == "15 bids")
        #expect(viewModel.priceLabel == "Current bid")
        #expect(viewModel.buyerMarker(at: launch) == .highBidder)
        #expect(viewModel.actionBar(at: launch) == .bidding(minimumBid: 25_000, buyNowPrice: nil))
    }

    @Test("BID-10: Buy Now ends the lot as purchased by you, with no actions")
    func buyNowMarksPurchased() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 30_000)
        let (viewModel, repository) = await makeViewModel(vehicle)
        let observing = await startObserving(viewModel)
        defer { observing.cancel() }

        await repository.buyNow(vehicle.id)
        await settle { viewModel.vehicle?.isPurchasedByYou == true }

        #expect(viewModel.buyerMarker(at: launch) == .purchased)
        #expect(viewModel.actionBar(at: launch) == .ended(.purchasedByYou))
    }

    // MARK: - LIVE-1 / LIVE-3 live updates

    @Test("LIVE-1: the view model starts from the repository's current copy")
    func startsFromCurrentCopy() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, _) = await makeViewModel(vehicle)

        #expect(viewModel.vehicle?.currentBid == 23_000)
    }

    @Test("LIVE-1 / LIVE-3: a competing bid updates the vehicle and the action bar minimum")
    func competingBidUpdatesDetail() async throws {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let stack = await makeStack(vehicle)
        let (viewModel, server) = (stack.viewModel, stack.server)
        let observing = await startObserving(viewModel)
        defer { observing.cancel() }

        try #require(server.simulateCompetingBid() != nil)
        await settle { viewModel.vehicle?.currentBid == 24_000 }

        #expect(viewModel.vehicle?.currentBid == 24_000)
        #expect(viewModel.bidCountText == "15 bids")
        #expect(viewModel.actionBar(at: launch) == .bidding(minimumBid: 25_000, buyNowPrice: nil))
        #expect(viewModel.buyerMarker(at: launch) == nil)
    }

    @Test("LIVE-3: your bid followed by a competing bid shows you as outbid")
    func competingBidOutbidsYou() async throws {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let stack = await makeStack(vehicle)
        let (viewModel, repository, server) = (stack.viewModel, stack.repository, stack.server)
        let observing = await startObserving(viewModel)
        defer { observing.cancel() }

        await repository.placeBid(24_000, on: vehicle.id)
        await settle { viewModel.vehicle?.currentBid == 24_000 }
        #expect(viewModel.buyerMarker(at: launch) == .highBidder)

        try #require(server.simulateCompetingBid() != nil)
        await settle { viewModel.vehicle?.currentBid == 25_000 }

        #expect(viewModel.buyerMarker(at: launch) == .outbid)
        #expect(viewModel.actionBar(at: launch) == .bidding(minimumBid: 26_000, buyNowPrice: nil))
    }

    @Test("LIVE-1: cancelling the observing task stops updates")
    func cancellingStopsUpdates() async throws {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let stack = await makeStack(vehicle)
        let (viewModel, repository, server) = (stack.viewModel, stack.repository, stack.server)
        let observing = await startObserving(viewModel)

        observing.cancel()
        await observing.value
        try #require(server.simulateCompetingBid() != nil)
        await settle { repository.vehicle(id: vehicle.id)?.currentBid == 24_000 }
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(repository.vehicle(id: vehicle.id)?.currentBid == 24_000)
        #expect(viewModel.vehicle?.currentBid == 23_000)
    }

    // MARK: - DETAIL-2 header

    @Test("DETAIL-2: lot without bids shows the starting bid")
    func startingPrice() async {
        let (viewModel, _) = await makeViewModel(.fixture(startingBid: 12_500))

        #expect(viewModel.priceLabel == "Starting at")
        #expect(viewModel.priceAmount == "$12,500")
        #expect(viewModel.bidCountText == "0 bids")
        #expect(viewModel.buyerMarker(at: launch) == nil)
    }

    // MARK: - DETAIL-3 / DETAIL-4 / DETAIL-5 sections

    @Test("DETAIL-3: spec rows list the vehicle's specs in display form")
    func specRows() async {
        let (viewModel, _) = await makeViewModel(.fixture())

        #expect(viewModel.specRows.map(\.label) == [
            "Engine", "Transmission", "Drivetrain", "Fuel", "Odometer", "Body style", "Exterior", "Interior"
        ])
        #expect(viewModel.specRows.map(\.value) == [
            "2.7L EcoBoost V6", "Automatic", "4WD", "Gasoline", "47,731 km", "SUV", "Burgundy", "Beige"
        ])
    }

    @Test("DETAIL-4: grade is formatted as x.x / 5")
    func gradeText() async {
        let (viewModel, _) = await makeViewModel(.fixture())

        #expect(viewModel.conditionGradeText == "3.8 / 5")
    }

    @Test("DETAIL-4: empty damage notes report no damage")
    func noDamage() async {
        let (viewModel, _) = await makeViewModel(.fixture())

        #expect(!viewModel.hasDamageNotes)
    }

    @Test("DETAIL-4: damage notes are reported when present")
    func damagePresent() async {
        let (viewModel, _) = await makeViewModel(.fixture().with(damageNotes: ["Scratch on rear bumper"]))

        #expect(viewModel.hasDamageNotes)
    }

    @Test("DETAIL-4: clean title is not flagged", arguments: [TitleStatus.clean])
    func cleanTitle(status: TitleStatus) async {
        let (viewModel, _) = await makeViewModel(.fixture().with(titleStatus: status))

        #expect(!viewModel.isTitleFlagged)
        #expect(viewModel.titleStatusText == "Clean")
    }

    @Test("DETAIL-4: rebuilt and salvage titles are flagged", arguments: [TitleStatus.rebuilt, .salvage])
    func flaggedTitle(status: TitleStatus) async {
        let (viewModel, _) = await makeViewModel(.fixture().with(titleStatus: status))

        #expect(viewModel.isTitleFlagged)
        #expect(viewModel.titleStatusText == status.rawValue.capitalized)
    }

    @Test("DETAIL-5: location combines city and province")
    func location() async {
        let (viewModel, _) = await makeViewModel(.fixture())

        #expect(viewModel.locationText == "Toronto, Ontario")
    }

}

/// View model plus the repository and stub server behind it.
@MainActor
private struct Stack {
    let viewModel: VehicleDetailViewModel
    let repository: VehicleRepository
    let server: SimulatedAuctionDataSource
}

@MainActor
private extension VehicleModel {

    /// Copy with the immutable condition fields replaced (the shared fixture doesn't expose them).
    func with(damageNotes: [String]? = nil, titleStatus: TitleStatus? = nil) -> VehicleModel {
        VehicleModel(
            id: id, vin: vin, year: year, make: make, model: model, trim: trim, bodyStyle: bodyStyle,
            exteriorColor: exteriorColor, interiorColor: interiorColor, engine: engine,
            transmission: transmission, drivetrain: drivetrain, odometerKm: odometerKm, fuelType: fuelType,
            conditionGrade: conditionGrade, conditionReport: conditionReport,
            damageNotes: damageNotes ?? self.damageNotes, titleStatus: titleStatus ?? self.titleStatus,
            province: province, city: city, auctionStart: auctionStart, startingBid: startingBid,
            reservePrice: reservePrice, buyNowPrice: buyNowPrice, images: images,
            sellingDealership: sellingDealership, lot: lot, currentBid: currentBid, bidCount: bidCount,
            yourBid: yourBid, yourPurchasePrice: yourPurchasePrice
        )
    }

}
