//
//  AuctionStatusBadge.swift
//  The Block
//
//  Reusable status pill with a live countdown, driven by the shared
//  AuctionTicker.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Status pill plus a live countdown for one vehicle (spec TIME-3, TIME-4).
///
/// Reads the app's shared auction clock, so a lot that starts or ends while on screen flips
/// state without every visible row creating its own timer.
struct AuctionStatusBadge: View {

    /// The lot whose status and countdown are shown.
    let vehicle: VehicleModel
    /// Freezes countdown rendering during active scrolling while live vehicle updates continue.
    var pausedAt: Date?

    /// Shared app clock; drives the countdown unless `pausedAt` is set.
    @Environment(AuctionTicker.self) private var ticker

    var body: some View {
        let now = pausedAt ?? ticker.now
        let status = vehicle.status(at: now)
        HStack(spacing: Spacing.xSmall) {
            // Primary text on a tinted pill with a status dot: tinted caption text fails contrast (UX-3).
            HStack(spacing: Spacing.xxSmall) {
                Circle()
                    .fill(status.tint(now: now))
                    .frame(width: Constants.dotSize, height: Constants.dotSize)
                    .accessibilityHidden(true)
                Text(status.badgeTitle)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xxSmall)
            .background(status.tint(now: now).opacity(0.15), in: Capsule())
            if let countdown = status.countdownText(now: now) {
                Text(countdown)
                    .font(.caption.monospacedDigit().weight(status.isEndingSoon(now: now) ? .semibold : .regular))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status.badge")
    }

}

/// Layout values for the status badge.
private enum Constants {
    /// Diameter of the status colour dot.
    static let dotSize: CGFloat = 6
}
