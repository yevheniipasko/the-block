import Foundation
import Testing
@testable import The_Block

@MainActor
struct VehicleDetailViewModelTests {

    /// With fewer than 121 vehicles the latest dataset start is mapped to `launch`.
    private let launch = TestDates.reference
    private let datasetAnchor = Date(timeIntervalSince1970: 1_000_000)

    private func makeViewModel(_ vehicle: VehicleModel) async -> (VehicleDetailViewModel, VehicleRepository) {
        let repository = VehicleRepository(
            dataSource: StubVehicleDataSource(result: .success([vehicle])),
            clock: FixedClock(now: launch)
        )
        await repository.load()
        return (VehicleDetailViewModel(vehicleID: vehicle.id, repository: repository), repository)
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

    @Test("BID-6: a bid placed through the repository shows on detail immediately")
    func bidUpdatesDetail() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle)

        await repository.placeBid(24_000, on: vehicle.id)

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

        await repository.buyNow(vehicle.id)

        #expect(viewModel.buyerMarker(at: launch) == .purchased)
        #expect(viewModel.actionBar(at: launch) == .ended(.purchasedByYou))
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
