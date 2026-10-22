import Foundation
import Testing
@testable import The_Block

@MainActor
struct VehicleRepositoryTests {

    private let launch = TestDates.reference

    private func makeRepository(_ vehicles: [VehicleModel]) async -> VehicleRepository {
        let repository = VehicleRepository.stubbed(
            result: .success(vehicles),
            clock: FixedClock(now: launch)
        )
        await repository.load()
        return repository
    }

    @Test("DATA-1 / TIME-1: load normalizes starts around launch time")
    func loadNormalizes() async {
        let datasetStart = Date(timeIntervalSince1970: 0)
        let repository = await makeRepository([.fixture(auctionStart: datasetStart)])

        #expect(repository.loadState == .loaded)
        #expect(repository.vehicles.first?.auctionStart == launch)
    }

    @Test("DATA-3: a failing data source leads to a failed state, not an empty list")
    func loadFailure() async {
        let repository = VehicleRepository.stubbed(
            result: .failure(StubError()),
            clock: FixedClock(now: launch)
        )

        await repository.load()

        guard case .failed = repository.loadState else {
            Issue.record("Expected failed state, got \(repository.loadState)")
            return
        }
    }

    @Test("BID-6: a placed bid updates current bid, count, and high-bidder state")
    func placeBidUpdatesState() async throws {
        let id = UUID()
        let repository = await makeRepository([.fixture(id: id, currentBid: 23_000, bidCount: 14)])

        let updated = try await repository.placeBid(24_000, on: id).get()

        #expect(updated.currentBid == 24_000)
        #expect(updated.bidCount == 15)
        #expect(updated.isYouHighBidder)
        #expect(repository.vehicle(id: id) == updated)
    }

    @Test("BID-3 / BID-8: a rejected bid leaves the vehicle unchanged")
    func rejectedBidLeavesStateUntouched() async {
        let id = UUID()
        let repository = await makeRepository([.fixture(id: id, currentBid: 23_000, bidCount: 14)])
        let before = repository.vehicle(id: id)

        let result = await repository.placeBid(23_500, on: id)

        #expect(result.failure == .belowMinimum(minimum: 24_000))
        #expect(repository.vehicle(id: id) == before)
    }

    @Test("BID-7: bidding on an ended lot is rejected by the repository")
    func endedLotRejectsBid() async {
        let id = UUID()
        // Two vehicles so this one's start can sit 73 h before the anchored launch time.
        let anchor = VehicleModel.fixture(auctionStart: Date(timeIntervalSince1970: 1_000_000))
        let endedStart = Date(timeIntervalSince1970: 1_000_000 - TestDates.hours(73))
        let ended = VehicleModel.fixture(id: id, auctionStart: endedStart)
        let repository = await makeRepository([ended, anchor])

        #expect(await repository.placeBid(50_000, on: id).failure == .auctionEnded)
    }

    @Test("BID-10: Buy Now marks the lot purchased by you")
    func buyNowPurchases() async throws {
        let id = UUID()
        let vehicle = VehicleModel.fixture(id: id, auctionStart: Date(timeIntervalSince1970: 0), buyNowPrice: 31_000)
        let repository = await makeRepository([vehicle])
        // The only vehicle is the anchor, so it starts exactly at launch → active.

        let updated = try await repository.buyNow(id).get()

        #expect(updated.isPurchasedByYou)
        #expect(updated.status(at: launch) == .ended(.purchasedByYou))
    }

    @Test("BID-11: Buy Now is rejected for lots without a price")
    func buyNowWithoutPrice() async {
        let id = UUID()
        let repository = await makeRepository([.fixture(id: id, buyNowPrice: nil)])

        #expect(await repository.buyNow(id).failure == .buyNowUnavailable)
    }

    @Test("LIST-7 / BID-6: pages reflect bids placed after loading")
    func pagesSeeLiveBids() async throws {
        let id = UUID()
        let repository = await makeRepository([.fixture(id: id, currentBid: 23_000, bidCount: 14)])
        await repository.placeBid(24_000, on: id)

        let page = try await repository.fetchPage(InventoryQuery(), after: nil, limit: 20)

        #expect(page.vehicles.first?.currentBid == 24_000)
        #expect(page.totalCount == 1)
    }

    @Test("Unknown vehicle IDs are rejected")
    func unknownVehicle() async {
        let repository = await makeRepository([.fixture()])

        #expect(await repository.placeBid(1_000, on: UUID()).failure == .vehicleNotFound)
        #expect(await repository.buyNow(UUID()).failure == .vehicleNotFound)
    }

}
