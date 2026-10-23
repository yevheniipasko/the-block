//
//  AuctionTicker.swift
//  The Block
//
//  Shared once-per-second clock that auction views observe instead of
//  running a timer per row.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Observation

/// One shared clock for auction UI. Views observe `now` without creating a timer per row.
///
/// Created once by the app and injected into the environment; status badges, detail, and the
/// action bar read it to keep countdowns and live states current (spec TIME-3, TIME-4).
@Observable
final class AuctionTicker {

    /// Current time, refreshed every second while `run()` is active.
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
