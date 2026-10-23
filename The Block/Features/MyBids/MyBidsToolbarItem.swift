//
//  MyBidsToolbarItem.swift
//  The Block
//
//  Inventory toolbar button that opens "My bids", with a badge counting
//  lots you've been outbid on.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Inventory toolbar entry that opens "My bids", badged with the number of lots you're outbid on
/// (spec MYBIDS-1, MYBIDS-6). The badge is hidden at 0.
///
/// Uses the system toolbar badge rather than a custom overlay: the Liquid Glass button clips its
/// label to the glass shape, which cut off an offset overlay after navigating back.
struct MyBidsToolbarItem: ToolbarContent {

    /// Lots you're outbid on; shown as the badge and the VoiceOver value.
    let outbidCount: Int
    /// Opens the "My bids" screen.
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: action) {
                Image(systemName: "hammer")
                    .accessibilityLabel(Localizable.title)
            }
            .badge(outbidCount)
            .accessibilityIdentifier("list.myBidsButton")
            .accessibilityValue(Localizable.outbidValue(outbidCount))
        }
    }

}

/// User-facing strings for the toolbar entry.
private enum Localizable {
    static let title = "My bids"
    static func outbidValue(_ count: Int) -> String {
        count == 0 ? "" : "Outbid on \(count)"
    }
}
