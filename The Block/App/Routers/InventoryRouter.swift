import Foundation
import Observation

/// Sheets presented over the inventory / detail screens.
enum BiddingSheet: Identifiable, Hashable {
    case bid(VehicleModel.ID)
    case buyNow(VehicleModel.ID)

    var id: Self { self }
}

/// Builds screen ViewModels. Implemented by `AppModule`, so the router never sees the container.
protocol ViewModelFactoryProtocol: AnyObject {
    func makeInventoryViewModel() -> InventoryViewModel
    func makeVehicleDetailViewModel(vehicleID: VehicleModel.ID) -> VehicleDetailViewModel
    func makeBidViewModel(vehicleID: VehicleModel.ID) -> BidViewModel
    func makeMyBidsViewModel() -> MyBidsViewModel
}

/// Navigation state for the whole app: selected vehicle (list → detail) and presented sheet.
protocol InventoryRouterProtocol: AnyObject {
    var inventoryViewModel: InventoryViewModel { get }
    var selectedVehicleID: VehicleModel.ID? { get }
    var detailViewModel: VehicleDetailViewModel? { get }
    var presentedSheet: BiddingSheet? { get }
    var bidViewModel: BidViewModel? { get }
    var myBidsViewModel: MyBidsViewModel { get }
    var isShowingMyBids: Bool { get }

    /// Shows a vehicle's detail, or clears it with `nil` (spec UX-1).
    func select(_ vehicleID: VehicleModel.ID?)
    /// Presents the bid sheet for a vehicle (spec BID-1).
    func presentBid(for vehicleID: VehicleModel.ID)
    /// Presents the Buy Now confirmation for a vehicle (spec BID-10).
    func presentBuyNow(for vehicleID: VehicleModel.ID)
    /// Closes any presented sheet.
    func dismissSheet()
    /// Opens "My bids" (spec MYBIDS-1).
    func showMyBids()
    /// Closes "My bids" and returns to the inventory list (spec MYBIDS-5).
    func hideMyBids()
}

@Observable
final class InventoryRouter: InventoryRouterProtocol {

    private(set) var selectedVehicleID: VehicleModel.ID?
    private(set) var detailViewModel: VehicleDetailViewModel?
    private(set) var presentedSheet: BiddingSheet?
    private(set) var bidViewModel: BidViewModel?
    private(set) var isShowingMyBids = false
    let inventoryViewModel: InventoryViewModel
    let myBidsViewModel: MyBidsViewModel

    @ObservationIgnored private unowned let factory: ViewModelFactoryProtocol

    init(factory: ViewModelFactoryProtocol) {
        self.factory = factory
        self.inventoryViewModel = factory.makeInventoryViewModel()
        self.myBidsViewModel = factory.makeMyBidsViewModel()
    }

    /// ViewModels are built here, on navigation, never inside a view's `body`.
    func select(_ vehicleID: VehicleModel.ID?) {
        guard vehicleID != selectedVehicleID else { return }
        selectedVehicleID = vehicleID
        detailViewModel = vehicleID.map { factory.makeVehicleDetailViewModel(vehicleID: $0) }
    }

    func presentBid(for vehicleID: VehicleModel.ID) {
        bidViewModel = factory.makeBidViewModel(vehicleID: vehicleID)
        presentedSheet = .bid(vehicleID)
    }

    func presentBuyNow(for vehicleID: VehicleModel.ID) {
        bidViewModel = factory.makeBidViewModel(vehicleID: vehicleID)
        presentedSheet = .buyNow(vehicleID)
    }

    func dismissSheet() {
        presentedSheet = nil
        bidViewModel = nil
    }

    func showMyBids() {
        isShowingMyBids = true
    }

    func hideMyBids() {
        isShowingMyBids = false
    }

}
