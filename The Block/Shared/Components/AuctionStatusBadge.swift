import SwiftUI

/// Status pill plus a live countdown for one vehicle (spec TIME-3, TIME-4).
///
/// Reads the app's shared auction clock, so a lot that starts or ends while on screen flips
/// state without every visible row creating its own timer.
struct AuctionStatusBadge: View {

    let vehicle: VehicleModel
    /// Freezes countdown rendering during active scrolling while live vehicle updates continue.
    var pausedAt: Date?

    @Environment(AuctionTicker.self) private var ticker

    var body: some View {
        let now = pausedAt ?? ticker.now
        let status = vehicle.status(at: now)
        HStack(spacing: Spacing.xSmall) {
            Label(status.badgeTitle, systemImage: status.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.xxSmall)
                .background(status.tint(now: now).opacity(0.15), in: Capsule())
                .foregroundStyle(status.tint(now: now))
            if let countdown = status.countdownText(now: now) {
                Text(countdown)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.isEndingSoon(now: now) ? .orange : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status.badge")
    }

}

private extension AuctionStatus {

    var systemImage: String {
        switch self {
        case .upcoming: "clock.fill"
        case .active: "circle.fill"
        case .ended: "flag.checkered"
        }
    }

}
