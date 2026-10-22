import Foundation

/// Source of "now", injectable so tests can pin time.
protocol AuctionClockProtocol: Sendable {
    /// The current moment, used for every status, countdown, and bid check (spec TIME-2, TIME-4).
    var now: Date { get }
}

/// Production clock that reads the device's wall-clock time.
struct SystemAuctionClock: AuctionClockProtocol {
    var now: Date { Date() }
}
