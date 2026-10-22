import Foundation

/// Maps the dataset's synthetic `auction_start` values onto real time (spec TIME-1).
///
/// All starts are shifted by one constant offset so that the launch time lands on the
/// 121st of the sorted start times (60th percentile). Spacing between auctions is preserved.
struct AuctionSchedule: Sendable {

    /// How long each auction runs after it starts (spec: 72 h).
    static let duration: TimeInterval = 72 * 60 * 60

    /// Index in the sorted start times that is mapped to launch time.
    static let anchorIndex = 120

    /// Constant shift added to every dataset start.
    let offset: TimeInterval

    /// Computes the offset that moves the anchor start onto `launchDate` (spec TIME-1).
    ///
    /// The anchor is the start at `anchorIndex` in sorted order; with fewer starts the last one is used,
    /// and an empty list gives a zero offset.
    ///
    /// - Parameters:
    ///   - datasetStarts: Raw `auction_start` values from the dataset, in any order.
    ///   - launchDate: The moment the anchor start should map to, usually app launch time.
    init(datasetStarts: [Date], launchDate: Date) {
        let sorted = datasetStarts.sorted()
        guard !sorted.isEmpty else {
            offset = 0
            return
        }
        let anchor = sorted[min(Self.anchorIndex, sorted.count - 1)]
        offset = launchDate.timeIntervalSince(anchor)
    }

    /// Shifts a dataset start into real time by the schedule's offset (spec TIME-1).
    func normalized(_ datasetStart: Date) -> Date {
        datasetStart.addingTimeInterval(offset)
    }

}
