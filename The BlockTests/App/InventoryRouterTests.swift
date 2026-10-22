import Foundation
import Testing
@testable import The_Block

@MainActor
private final class FakeViewModelFactory: ViewModelFactoryProtocol {

    let repository = VehicleRepository.stubbed(
        result: .success([]),
        clock: FixedClock(now: TestDates.reference)
    )
    private(set) var detailRequests: [VehicleModel.ID] = []

    func makeInventoryViewModel() -> InventoryViewModel {
        InventoryViewModel(repository: repository)
    }

    func makeVehicleDetailViewModel(vehicleID: VehicleModel.ID) -> VehicleDetailViewModel {
        detailRequests.append(vehicleID)
        return VehicleDetailViewModel(vehicleID: vehicleID, repository: repository)
    }

    func makeBidViewModel(vehicleID: VehicleModel.ID) -> BidViewModel {
        BidViewModel(vehicleID: vehicleID, repository: repository)
    }

}

@MainActor
struct InventoryRouterTests {

    private let factory = FakeViewModelFactory()

    @Test("UX-1: selecting a vehicle builds its detail ViewModel once")
    func selectBuildsDetailOnce() {
        let router = InventoryRouter(factory: factory)
        let id = UUID()

        router.select(id)
        router.select(id)

        #expect(router.selectedVehicleID == id)
        #expect(router.detailViewModel?.vehicleID == id)
        #expect(factory.detailRequests == [id])
    }

    @Test("UX-1: clearing the selection drops the detail ViewModel")
    func clearSelection() {
        let router = InventoryRouter(factory: factory)
        router.select(UUID())

        router.select(nil)

        #expect(router.detailViewModel == nil)
    }

    @Test("BID-1 / BID-10: presenting a sheet builds its ViewModel; dismissing clears both")
    func sheets() {
        let router = InventoryRouter(factory: factory)
        let id = UUID()

        router.presentBid(for: id)
        #expect(router.presentedSheet == .bid(id))
        #expect(router.bidViewModel?.vehicleID == id)

        router.presentBuyNow(for: id)
        #expect(router.presentedSheet == .buyNow(id))

        router.dismissSheet()
        #expect(router.presentedSheet == nil)
        #expect(router.bidViewModel == nil)
    }

}
