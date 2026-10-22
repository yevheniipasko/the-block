import Foundation

/// Where a vehicle's auction is at a given moment (spec TIME-2).
enum AuctionStatus: Hashable, Sendable {

    case upcoming(startsAt: Date)
    case active(endsAt: Date)
    case ended(EndedOutcome)

    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }

}

enum EndedOutcome: Hashable, Sendable {
    /// Bought through Buy Now, or won as high bidder with the floor met.
    case purchasedByYou
    /// Someone else won with the floor met (or no floor).
    case sold
    /// Highest bid stayed below the floor; the seller decides (not simulated).
    case pendingBelowFloor
    /// The auction ended without bids.
    case noSale
}

/// Whether the current bid reaches the seller's floor (reserve) price.
/// The floor amount itself is never shown to the buyer.
enum FloorState: Hashable, Sendable {
    case noFloor
    case met
    case notMet
}

extension VehicleModel {

    var floorState: FloorState {
        guard let reservePrice else { return .noFloor }
        guard let currentBid, currentBid >= reservePrice else { return .notMet }
        return .met
    }

    func status(at now: Date) -> AuctionStatus {
        if isPurchasedByYou {
            return .ended(.purchasedByYou)
        }
        if now < auctionStart {
            return .upcoming(startsAt: auctionStart)
        }
        if now < auctionEnd {
            return .active(endsAt: auctionEnd)
        }
        return .ended(endedOutcome)
    }

    private var endedOutcome: EndedOutcome {
        guard bidCount > 0 else { return .noSale }
        guard floorState != .notMet else { return .pendingBelowFloor }
        return isYouHighBidder ? .purchasedByYou : .sold
    }

}
