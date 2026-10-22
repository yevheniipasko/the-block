import SwiftUI

/// Status pill plus a live countdown for one vehicle (spec TIME-3, TIME-4).
///
/// Redraws every second through `TimelineView`, so a lot that starts or ends while on
/// screen flips state without a reload.
struct AuctionStatusBadge: View {

    let vehicle: VehicleModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = vehicle.status(at: context.date)
            HStack(spacing: Spacing.xSmall) {
                Text(status.badgeTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(status.tint(now: context.date).opacity(0.15), in: Capsule())
                    .foregroundStyle(status.tint(now: context.date))
                if let countdown = status.countdownText(now: context.date) {
                    Text(countdown)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(status.isEndingSoon(now: context.date) ? .orange : .secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("status.badge")
        }
    }

}
