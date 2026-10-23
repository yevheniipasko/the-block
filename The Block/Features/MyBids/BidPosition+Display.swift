//
//  BidPosition+Display.swift
//  The Block
//
//  Display wording, SF Symbols, tints, and test identifiers for each
//  BidPosition on the "My bids" screen.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Buyer-facing wording, icon, and colour for each position on the "My bids" screen (spec MYBIDS-2, MYBIDS-3).
extension BidPosition {

    /// Group header, e.g. `Winning`.
    var groupTitle: String {
        switch self {
        case .winning: Localizable.winning
        case .outbid: Localizable.outbid
        case .won: Localizable.won
        case .bought: Localizable.bought
        case .lost: Localizable.lost
        }
    }

    /// Short row badge, e.g. `You're winning`.
    var badgeTitle: String {
        switch self {
        case .winning: Localizable.winningBadge
        case .outbid: Localizable.outbidBadge
        case .won: Localizable.wonBadge
        case .bought: Localizable.boughtBadge
        case .lost: Localizable.lostBadge
        }
    }

    /// SF Symbol shown next to the row badge.
    var systemImage: String {
        switch self {
        case .winning: "checkmark.seal.fill"
        case .outbid: "exclamationmark.triangle.fill"
        case .won: "trophy.fill"
        case .bought: "bag.fill"
        case .lost: "xmark.circle.fill"
        }
    }

    /// Badge colour: green winning, red outbid, accent for owned lots, secondary when lost.
    var tint: Color {
        switch self {
        case .winning: .green
        case .outbid: .red
        case .won, .bought: .accentColor
        case .lost: .secondary
        }
    }

    /// Identifier fragment for UI tests, e.g. `mybids.group.winning`.
    var identifier: String {
        switch self {
        case .winning: "winning"
        case .outbid: "outbid"
        case .won: "won"
        case .bought: "bought"
        case .lost: "lost"
        }
    }

}

/// User-facing strings for bid positions.
private enum Localizable {
    static let winning = "Winning"
    static let outbid = "Outbid"
    static let won = "Won"
    static let bought = "Bought"
    static let lost = "Lost"
    static let winningBadge = "You're winning"
    static let outbidBadge = "You've been outbid"
    static let wonBadge = "You won"
    static let boughtBadge = "Bought with Buy Now"
    static let lostBadge = "Not won"
}
