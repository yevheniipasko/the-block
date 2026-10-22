import Foundation
import Testing
@testable import The_Block

@MainActor
struct DetailOutbidMarkerTests {

    @Test("LIVE-3: the outbid marker hides once the lot has ended")
    func outbidHiddenAfterEnd() async {
        let launch = TestDates.reference
        let anchorStart = Date(timeIntervalSince1970: 1_000_000)
        let lostLotID = UUID()
        // Fewer than 121 lots: the latest start becomes "now", so the other lot has ended.
        let anchor = VehicleModel.fixture(auctionStart: anchorStart)
        let lost = VehicleModel.fixture(
            id: lostLotID,
            auctionStart: anchorStart.addingTimeInterval(-TestDates.hours(73)),
            currentBid: 21_000,
            bidCount: 4,
            yourBid: 20_000
        )
        let repository = VehicleRepository.stubbed(result: .success([anchor, lost]), clock: FixedClock(now: launch))
        await repository.load()

        let viewModel = VehicleDetailViewModel(vehicleID: lostLotID, repository: repository)

        #expect(viewModel.vehicle?.isYouOutbid == true)
        #expect(viewModel.buyerMarker(at: launch) == nil)
    }

}
