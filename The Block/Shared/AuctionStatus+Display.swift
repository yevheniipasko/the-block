//
//  AuctionStatus+Display.swift
//  The Block
//
//  Display wording and colours for AuctionStatus, EndedOutcome, and
//  FloorState, shared by list and detail screens.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Buyer-facing wording and colours for auction states, shared by list and detail.
extension AuctionStatus {

    /// Auctions closing within this window get "Ending soon" emphasis (spec TIME-3).
    static let endingSoonWindow: TimeInterval = 60 * 60

    /// Short badge title, e.g. `Live`, `Upcoming`, `Sold`.
    var badgeTitle: String {
        switch self {
        case .upcoming: "Upcoming"
        case .active: "Live"
        case .ended(let outcome): outcome.title
        }
    }

    /// Countdown line for live states, `nil` once the auction has ended (spec TIME-3).
    func countdownText(now: Date) -> String? {
        switch self {
        case .upcoming(let startsAt): "Starts in \(Formatting.countdown(from: now, to: startsAt))"
        case .active(let endsAt): "Ends in \(Formatting.countdown(from: now, to: endsAt))"
        case .ended: nil
        }
    }

    /// Whether an active auction closes within `endingSoonWindow`.
    func isEndingSoon(now: Date) -> Bool {
        guard case .active(let endsAt) = self else { return false }
        return endsAt.timeIntervalSince(now) < Self.endingSoonWindow
    }

    /// Badge colour: green live, orange ending soon, blue upcoming, outcome colour once ended.
    func tint(now: Date) -> Color {
        switch self {
        case .upcoming: .blue
        case .active: isEndingSoon(now: now) ? .orange : .green
        case .ended(let outcome): outcome.tint
        }
    }

}

extension EndedOutcome {

    /// OPENLANE-style result wording.
    var title: String {
        switch self {
        case .purchasedByYou: "Purchased by you"
        case .sold: "Sold"
        case .pendingBelowFloor: "Pending – below floor"
        case .noSale: "No sale"
        }
    }

    var tint: Color {
        switch self {
        case .purchasedByYou: .accentColor
        case .sold, .noSale: .secondary
        case .pendingBelowFloor: .orange
        }
    }

}

extension FloorState {

    /// Buyer-facing floor wording; the floor amount itself is never shown.
    var title: String {
        switch self {
        case .noFloor: "No floor"
        case .met: "Floor met"
        case .notMet: "Floor not met"
        }
    }

}
