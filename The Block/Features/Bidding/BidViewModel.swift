//
//  BidViewModel.swift
//  The Block
//
//  State for the bid and Buy Now sheets: live lot copy, amount entry, validation,
//  fee estimates and the submit flow (spec BID-*, LIVE-3, FEES-1).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Observation
import OSLog

/// Bid sheet and Buy Now confirmation state for one vehicle (spec BID-1 … BID-11, LIVE-3).
///
/// Keeps its own copy of the lot, kept current by `observeVehicle()` while the sheet is open,
/// so the minimum, step, outbid notice and availability follow other bidders and the clock.
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

    /// Latest known copy of the lot; `nil` if it is not listed.
    private(set) var vehicle: VehicleModel?
    /// The moment rules are evaluated at; refreshed on every update and clock tick.
    private(set) var now: Date
    /// Digits-only bid entry, pre-filled with the minimum next bid (spec BID-1, BID-2).
    private(set) var amountText: String
    /// Current step of the flow; the sheets pick what to show from it.
    private(set) var phase: Phase = .editing
    /// Why the last submission was refused; cleared as soon as the amount changes (spec BID-8).
    private(set) var rejectionMessage: String?

    @ObservationIgnored private let clockTick: Duration
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "BidViewModel")

    /// Creates the state for one vehicle and pre-fills the entry with its minimum next bid (spec BID-1).
    ///
    /// - Parameters:
    ///   - vehicleID: The lot the sheet is for.
    ///   - repository: Source of the lot's live state and the bid / Buy Now endpoints.
    ///   - clockTick: How often `observeVehicle()` re-checks the clock so a lot that ends while the
    ///     sheet is open flips to its ended state; shorter in tests.
    init(vehicleID: VehicleModel.ID, repository: VehicleRepositoryProtocol, clockTick: Duration = .seconds(1)) {
        self.vehicleID = vehicleID
        self.repository = repository
        self.clockTick = clockTick
        let vehicle = repository.vehicle(id: vehicleID)
        self.vehicle = vehicle
        self.now = repository.now
        self.amountText = vehicle.map { String(BiddingRules.minimumNextBid(for: $0)) } ?? ""
    }

    // MARK: - Live updates

    /// Follows the lot until cancelled: applies every update and re-checks the clock each tick (spec LIVE-1, LIVE-3).
    ///
    /// Call from the sheet's `.task`, which cancels it when the sheet closes.
    func observeVehicle() async {
        // Subscribe before the first suspension, so no update between here and the loop is missed.
        let updates = repository.vehicleUpdates(id: vehicleID)
        let ticker = Task { [weak self, clockTick] in
            while !Task.isCancelled {
                try? await Task.sleep(for: clockTick)
                self?.refreshClock()
            }
        }
        defer { ticker.cancel() }
        for await vehicle in updates {
            apply(vehicle)
        }
    }

    /// Stores a newer copy of the lot and re-validates the entry against it (spec LIVE-3).
    ///
    /// The typed amount is kept. A lot that was unknown when the sheet opened gets its minimum
    /// pre-filled now. A price change makes an earlier "Not placed" reason stale, so it is dropped.
    private func apply(_ updated: VehicleModel) {
        let previous = vehicle
        vehicle = updated
        now = repository.now
        if previous == nil, amountText.isEmpty {
            amountText = String(BiddingRules.minimumNextBid(for: updated))
        }
        if let previous, previous.currentBid != updated.currentBid {
            rejectionMessage = nil
        }
        leaveReviewIfInvalid()
    }

    /// Moves `now` forward so time-based states (ended, Buy Now window) update on screen (spec BID-7, BID-11).
    private func refreshClock() {
        now = repository.now
        leaveReviewIfInvalid()
    }

    /// Sends the buyer back to editing when the reviewed amount is no longer valid (spec LIVE-3, BID-3).
    private func leaveReviewIfInvalid() {
        guard phase == .reviewing, validationRejection != nil else { return }
        phase = .editing
    }

    /// Whether to show "You've been outbid": another bidder passed the buyer's bid on a live lot (spec LIVE-3).
    var isOutbid: Bool {
        guard let vehicle, !isAuctionEnded else { return false }
        return vehicle.isYouOutbid
    }

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

    // MARK: - Fee estimate

    /// Estimated total for the entered amount, or `nil` while the field is empty or zero (spec FEES-1).
    ///
    /// Follows every keystroke and quick-add, including amounts that don't pass validation yet,
    /// so the buyer sees the cost while typing.
    var bidEstimate: FeeEstimate? {
        guard let amount, amount > 0 else { return nil }
        return FeeSchedule.estimate(for: amount)
    }

    /// Estimated total for buying at the lot's Buy Now price, or `nil` when it has none (spec FEES-1).
    var buyNowEstimate: FeeEstimate? {
        vehicle?.buyNowPrice.map { FeeSchedule.estimate(for: $0) }
    }

    // MARK: - Validation

    /// Whether the lot can no longer take bids, so the sheet hides its controls (spec BID-7).
    var isAuctionEnded: Bool {
        guard let vehicle else { return true }
        return vehicle.status(at: now).isEnded
    }

    /// Why the current entry can't be placed, checked with `BiddingRules` against live state (spec BID-3, BID-4).
    var validationRejection: BidRejection? {
        guard let vehicle else { return .vehicleNotFound }
        let result = BiddingRules.validateBid(amount ?? 0, on: vehicle, at: now)
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
        case .success(let updated):
            vehicle = updated
            now = repository.now
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
        switch vehicle.status(at: now) {
        case .upcoming: return Localizable.buyNowNotOpenYet
        case .ended(.purchasedByYou): return Localizable.alreadyPurchased
        case .ended: return Localizable.message(for: .auctionEnded)
        case .active: return nil
        }
    }

    /// Buys the lot at its Buy Now price; ignored while a request is in flight or after success (spec BID-10).
    func buyNow() async {
        guard phase == .editing, buyNowUnavailableReason == nil else { return }
        phase = .submitting
        switch await repository.buyNow(vehicleID) {
        case .success(let updated):
            vehicle = updated
            now = repository.now
            phase = .succeeded
        case .failure(let rejection):
            handle(rejection)
        }
    }

    /// Logs a refused request, shows its reason and returns to editing (spec BID-8, LIVE-4).
    ///
    /// Rejections never change the lot. The lot and the clock are re-read first, so the shown
    /// minimum matches what the server refused against.
    private func handle(_ rejection: BidRejection) {
        logger.info("[BidViewModel] request rejected: \(String(describing: rejection), privacy: .public)")
        vehicle = repository.vehicle(id: vehicleID)
        now = repository.now
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
    static let alreadyPurchased = "You bought this lot."

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
        case .connectionFailed:
            "Couldn't reach the auction. Check your connection and try again."
        }
    }
}
