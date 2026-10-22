import Foundation
import Observation
import OSLog

/// Bid sheet and Buy Now confirmation state for one vehicle (spec BID-1 … BID-11).
///
/// Reads the live vehicle from the repository on every access, so the minimum, step and
/// availability always reflect the latest state — including changes made while a bid was
/// in flight.
@Observable
final class BidViewModel {

    /// Where the buyer is in the bid / Buy Now flow.
    enum Phase: Hashable {
        /// Entering an amount (bid sheet) or looking at the Buy Now confirmation.
        case editing
        /// Reviewing the bid before it is placed (spec BID-5).
        case reviewing
        /// Waiting for the repository round trip (spec UX-5).
        case submitting
        /// The bid or purchase went through (spec BID-8).
        case succeeded
    }

    let vehicleID: VehicleModel.ID
    @ObservationIgnored let repository: VehicleRepositoryProtocol

    /// Digits-only bid entry, pre-filled with the minimum next bid (spec BID-1, BID-2).
    private(set) var amountText: String
    private(set) var phase: Phase = .editing
    /// Why the last submission was refused; cleared as soon as the amount changes (spec BID-8).
    private(set) var rejectionMessage: String?

    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "BidViewModel")

    /// Creates the state for one vehicle and pre-fills the entry with its minimum next bid (spec BID-1).
    init(vehicleID: VehicleModel.ID, repository: VehicleRepositoryProtocol) {
        self.vehicleID = vehicleID
        self.repository = repository
        let minimum = repository.vehicle(id: vehicleID).map { BiddingRules.minimumNextBid(for: $0) }
        self.amountText = minimum.map(String.init) ?? ""
    }

    /// Latest repository copy of the lot; `nil` if it is no longer listed.
    var vehicle: VehicleModel? { repository.vehicle(id: vehicleID) }

    // MARK: - Bid entry

    /// Entered amount in whole dollars, or `nil` when the field is empty.
    var amount: Int? { Int(amountText) }

    /// Minimum next bid for the lot's live state (spec BID-1).
    var minimumBid: Int? { vehicle.map { BiddingRules.minimumNextBid(for: $0) } }

    /// Adaptive step the quick-add buttons use for this lot (spec BID-9).
    var bidStep: Int? {
        guard let vehicle else { return nil }
        return BiddingRules.step(currentBid: vehicle.currentBid ?? vehicle.startingBid, bidCount: vehicle.bidCount)
    }

    /// Explains the pre-filled minimum (spec BID-1).
    ///
    /// Lots with bids read "Minimum $24,000 · step $1,000 · Hot lot, 14 bids";
    /// lots without bids read "Opening bid $14,500".
    var minimumExplanation: String {
        guard let vehicle, let minimumBid, let bidStep else { return "" }
        let activity = ActivityLevel(bidCount: vehicle.bidCount)
        guard let activityName = Localizable.activityName(activity) else {
            return Localizable.openingBid(Formatting.currency(minimumBid))
        }
        return Localizable.minimumExplanation(
            minimum: Formatting.currency(minimumBid),
            step: Formatting.currency(bidStep),
            activity: activityName,
            bids: Localizable.bidCount(vehicle.bidCount)
        )
    }

    /// Replaces the entry with its digits only, so the amount is always whole dollars (spec BID-2).
    func updateAmountText(_ text: String) {
        guard phase == .editing else { return }
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(Constants.maxAmountDigits))
        guard digits != amountText else { return }
        amountText = digits
        rejectionMessage = nil
    }

    /// Adds `steps` adaptive steps to the current entry, or to the minimum when the field is empty (spec BID-2).
    func quickAdd(steps: Int) {
        guard phase == .editing, let bidStep, let base = amount ?? minimumBid else { return }
        updateAmountText(String(base + steps * bidStep))
    }

    // MARK: - Validation

    /// Whether the lot can no longer take bids, so the sheet hides its controls (spec BID-7).
    var isAuctionEnded: Bool {
        guard let vehicle else { return true }
        return vehicle.status(at: repository.now).isEnded
    }

    /// Why the current entry can't be placed, checked with `BiddingRules` against live state (spec BID-3, BID-4).
    var validationRejection: BidRejection? {
        guard let vehicle else { return .vehicleNotFound }
        let result = BiddingRules.validateBid(amount ?? 0, on: vehicle, at: repository.now)
        if case .failure(let rejection) = result {
            return rejection
        }
        return nil
    }

    /// Inline message under the amount: the last refused submission first, then live validation.
    var validationMessage: String? {
        rejectionMessage ?? validationRejection.map { Localizable.message(for: $0) }
    }

    /// Whether "Review bid" is enabled: editing, and the entry passes validation (spec BID-3, BID-4).
    var canReview: Bool { phase == .editing && validationRejection == nil }

    /// Whether a request is in flight; the sheet then locks its inputs and dismissal (spec UX-5).
    var isSubmitting: Bool { phase == .submitting }

    // MARK: - Bid flow

    /// Moves from entry to the confirmation step when the amount is valid (spec BID-5).
    func review() {
        guard canReview else { return }
        rejectionMessage = nil
        phase = .reviewing
    }

    /// Returns from the confirmation step to editing the amount.
    func editBid() {
        guard phase == .reviewing else { return }
        phase = .editing
    }

    /// Places the reviewed bid; ignored unless the sheet is on the confirmation step (spec BID-5, BID-8).
    ///
    /// On rejection (the lot may have changed during the round trip) the sheet goes back to
    /// editing with the reason shown; the repository leaves the vehicle untouched.
    func submitBid() async {
        guard phase == .reviewing, let amount else { return }
        phase = .submitting
        switch await repository.placeBid(amount, on: vehicleID) {
        case .success:
            phase = .succeeded
        case .failure(let rejection):
            handle(rejection)
        }
    }

    // MARK: - Buy Now

    /// Why Buy Now can't be offered right now, or `nil` when it can (spec BID-11).
    var buyNowUnavailableReason: String? {
        guard let vehicle else { return Localizable.message(for: .vehicleNotFound) }
        guard vehicle.buyNowPrice != nil else { return Localizable.noBuyNowPrice }
        switch vehicle.status(at: repository.now) {
        case .upcoming: return Localizable.buyNowNotOpenYet
        case .ended: return Localizable.message(for: .auctionEnded)
        case .active: return nil
        }
    }

    /// Buys the lot at its Buy Now price; ignored while a request is in flight or after success (spec BID-10).
    func buyNow() async {
        guard phase == .editing, buyNowUnavailableReason == nil else { return }
        phase = .submitting
        switch await repository.buyNow(vehicleID) {
        case .success:
            phase = .succeeded
        case .failure(let rejection):
            handle(rejection)
        }
    }

    /// Logs a refused request, shows its reason and returns to editing so nothing is left half-updated (spec BID-8).
    private func handle(_ rejection: BidRejection) {
        logger.info("[BidViewModel] request rejected: \(String(describing: rejection), privacy: .public)")
        rejectionMessage = Localizable.notPlaced(Localizable.message(for: rejection))
        phase = .editing
    }

}

private enum Constants {
    /// Nine digits keeps any entry well inside `Int` and above any realistic bid.
    static let maxAmountDigits = 9
}

private enum Localizable {
    static let noBuyNowPrice = "This lot has no Buy Now price."
    static let buyNowNotOpenYet = "Buy Now opens when the auction goes live."

    static func openingBid(_ amount: String) -> String { "Opening bid \(amount)" }

    static func minimumExplanation(minimum: String, step: String, activity: String, bids: String) -> String {
        "Minimum \(minimum) · step \(step) · \(activity), \(bids)"
    }

    static func bidCount(_ count: Int) -> String { count == 1 ? "1 bid" : "\(count) bids" }

    static func activityName(_ level: ActivityLevel) -> String? {
        switch level {
        case .opening: nil
        case .quiet: "Quiet lot"
        case .active: "Active lot"
        case .hot: "Hot lot"
        }
    }

    static func notPlaced(_ reason: String) -> String { "Not placed. \(reason)" }

    static func message(for rejection: BidRejection) -> String {
        switch rejection {
        case .auctionEnded:
            "This auction has ended."
        case .belowMinimum(let minimum):
            "Bid at least \(Formatting.currency(minimum))."
        case .atOrAboveBuyNow(let buyNowPrice):
            "Use Buy Now instead. Bids must be below \(Formatting.currency(buyNowPrice))."
        case .buyNowUnavailable:
            "Buy Now is no longer available."
        case .vehicleNotFound:
            "This vehicle is no longer listed."
        }
    }
}
