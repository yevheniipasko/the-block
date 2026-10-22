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

    let offset: TimeInterval

    init(datasetStarts: [Date], launchDate: Date) {
        let sorted = datasetStarts.sorted()
        guard !sorted.isEmpty else {
            offset = 0
            return
        }
        let anchor = sorted[min(Self.anchorIndex, sorted.count - 1)]
        offset = launchDate.timeIntervalSince(anchor)
    }

    func normalized(_ datasetStart: Date) -> Date {
        datasetStart.addingTimeInterval(offset)
    }

}
