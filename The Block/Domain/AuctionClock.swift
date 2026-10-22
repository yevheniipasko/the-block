import Foundation

/// Source of "now", injectable so tests can pin time.
protocol AuctionClockProtocol: Sendable {
    var now: Date { get }
}

struct SystemAuctionClock: AuctionClockProtocol {
    var now: Date { Date() }
}
