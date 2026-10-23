import Foundation
import Observation

/// One shared clock for auction UI. Views observe `now` without creating a timer per row.
@Observable
final class AuctionTicker {

    private(set) var now = Date.now

    /// Advances the shared time once per second until the owning SwiftUI task is cancelled.
    func run() async {
        while !Task.isCancelled {
            now = .now
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

}
